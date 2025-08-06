import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'flutter_libnfc_bindings.dart';

// --- Public API ---

/// High-level controller for NFC operations.
///
/// This class manages the native `libnfc` resources and runs blocking
/// NFC operations on a separate isolate to avoid blocking the main UI thread.
class NfcController {
  NfcController() {
    _initialize();
  }

  static int _nextRequestId = 0;
  final Map<int, Completer<dynamic>> _requests = {};
  late final SendPort _helperIsolateSendPort;
  bool _isInitialized = false;

  /// Initializes the controller and spawns the helper isolate.
  Future<void> _initialize() async {
    if (_isInitialized) return;

    final completer = Completer<SendPort>();

    // This port listens for the SendPort from the helper isolate
    final mainReceivePort = ReceivePort()
      ..listen((message) {
        if (message is SendPort) {
          // First message is the SendPort for communication
          completer.complete(message);
        } else if (message is _NfcResponse) {
          // Subsequent messages are responses to requests
          final requestCompleter = _requests.remove(message.id);
          if (requestCompleter != null) {
            if (message.error != null) {
              requestCompleter.completeError(Exception(message.error));
            } else {
              requestCompleter.complete(message.result);
            }
          }
        }
      });

    // Spawn the helper isolate, giving it a port to reply on
    await Isolate.spawn(
      _nfcIsolate,
      mainReceivePort.sendPort,
      debugName: 'NfcHelperIsolate',
    );

    // Wait for the helper isolate to send back its SendPort
    _helperIsolateSendPort = await completer.future;
    _isInitialized = true;
  }

  /// Sends a request to the helper isolate and returns a future with the result.
  Future<T> _sendRequest<T>(_NfcRequest request) async {
    await _initialize(); // Ensure initialized before sending
    final completer = Completer<T>();
    _requests[request.id] = completer;
    _helperIsolateSendPort.send(request);
    return completer.future;
  }

  /// Polls for a nearby NFC tag.
  ///
  /// This is an asynchronous operation that will complete when a tag is found,
  /// or timeout if no tag is found within the specified duration.
  /// Returns an [NfcTag] with UID and ATR information.
  Future<NfcTag> poll({Duration timeout = const Duration(seconds: 5)}) async {
    final request = _PollRequest(_nextRequestId++, timeout.inMilliseconds);
    final result = await _sendRequest<Map<String, dynamic>>(request);
    return NfcTag.fromMap(result);
  }

  /// Disposes of the NFC controller and releases all native resources.
  void dispose() {
    // No need to wait for initialization to dispose
    if (_isInitialized) {
      final request = _DisposeRequest(_nextRequestId++);
      _helperIsolateSendPort.send(request);
    }
  }
}

/// Represents a discovered NFC tag.
class NfcTag {
  /// The Unique Identifier of the tag.
  final List<int> uid;

  /// The Answer to Reset data from the tag.
  final List<int> atr;

  NfcTag({required this.uid, required this.atr});

  factory NfcTag.fromMap(Map<String, dynamic> map) {
    return NfcTag(
      uid: List<int>.from(map['uid']),
      atr: List<int>.from(map['atr']),
    );
  }

  @override
  String toString() {
    return 'NfcTag(uid: $uid, atr: $atr)';
  }
}

// --- Isolate Communication and Setup ---

final String _libName = 'nfc';

/// The dynamic library in which the symbols for [FlutterLibnfcBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final FlutterLibnfcBindings _bindings = FlutterLibnfcBindings(_dylib);

// --- Message classes for Isolate communication ---

abstract class _NfcRequest {
  final int id;
  const _NfcRequest(this.id);
}

class _PollRequest extends _NfcRequest {
  final int timeout;
  const _PollRequest(int id, this.timeout) : super(id);
}

class _DisposeRequest extends _NfcRequest {
  const _DisposeRequest(int id) : super(id);
}

class _NfcResponse {
  final int id;
  final dynamic result;
  final String? error;

  const _NfcResponse(this.id, this.result, {this.error});
}

// --- NFC Helper Isolate ---

/// The entry point for the helper isolate.
///
/// This isolate handles all the blocking native calls to `libnfc`.
void _nfcIsolate(SendPort mainSendPort) {
  Pointer<Pointer<nfc_context>> context = calloc<Pointer<nfc_context>>();
  Pointer<nfc_device>? pnd; // NFC device pointer

  _bindings.nfc_init(context);
  if (context.value == nullptr) {
    mainSendPort.send(_NfcResponse(0, null, error: 'nfc_init failed'));
    calloc.free(context);
    return;
  }

  final helperReceivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is _PollRequest) {
        try {
          // Open the NFC device
          pnd = _bindings.nfc_open(context.value, nullptr);
          if (pnd == nullptr) {
            throw Exception('Failed to open NFC device');
          }

          // Initialize as an initiator
          if (_bindings.nfc_initiator_init(pnd!) < 0) {
            throw Exception('Failed to init initiator');
          }

          // Poll for a target
          final Pointer<nfc_target> pnt = calloc<nfc_target>();
          final Pointer<nfc_modulation> pnm = calloc<nfc_modulation>();
          pnm.ref.nmtAsInt = nfc_modulation_type.NMT_ISO14443A.value;
          pnm.ref.nbrAsInt = nfc_baud_rate.NBR_106.value;

          final int res = _bindings.nfc_initiator_poll_target(
            pnd!,
            pnm,
            1,
            255,
            2,
            pnt,
          );

          if (res > 0) {
            final nfc_iso14443a_info nai = pnt.ref.nti.nai;

            // Correct way to convert ffi.Array<Uint8> to List<int>
            final uid = <int>[];
            for (var i = 0; i < nai.szUidLen; i++) {
              uid.add(nai.abtUid[i]);
            }

            final atr = <int>[];
            for (var i = 0; i < nai.szAtsLen; i++) {
              atr.add(nai.abtAts[i]);
            }

            final result = {'uid': uid, 'atr': atr};
            mainSendPort.send(_NfcResponse(data.id, result));
          } else if (res == 0) {
            mainSendPort.send(
              _NfcResponse(data.id, null, error: 'No tag found'),
            );
          } else {
            final error = _bindings.nfc_strerror(pnd!);
            final errorStr = error == nullptr
                ? 'Unknown error'
                : error.cast<Utf8>().toDartString();
            throw Exception('Error polling for target: $errorStr');
          }

          calloc.free(pnt);
          calloc.free(pnm);
        } catch (e) {
          mainSendPort.send(_NfcResponse(data.id, null, error: e.toString()));
        } finally {
          if (pnd != null) {
            _bindings.nfc_close(pnd!);
            pnd = null;
          }
        }
      } else if (data is _DisposeRequest) {
        if (pnd != null) {
          _bindings.nfc_close(pnd!);
        }
        _bindings.nfc_exit(context.value);
        calloc.free(context);
        Isolate.current.kill();
      }
    });

  // Send the port to the main isolate on which we can receive requests.
  mainSendPort.send(helperReceivePort.sendPort);
}
