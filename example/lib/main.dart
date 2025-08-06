import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_libnfc/flutter_libnfc.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final NfcController _nfcController;
  NfcTag? _tag;
  String? _error;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _nfcController = NfcController();
  }

  @override
  void dispose() {
    _nfcController.dispose();
    super.dispose();
  }

  Future<void> _pollForTag() async {
    setState(() {
      _isPolling = true;
      _tag = null;
      _error = null;
    });

    try {
      final tag = await _nfcController.poll();
      setState(() {
        _tag = tag;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isPolling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Flutter LibNFC Example')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isPolling)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: _pollForTag,
                    child: const Text('Poll for NFC Tag'),
                  ),
                const SizedBox(height: 20),
                if (_isPolling)
                  const Text('Please hold a tag near the reader...'),
                if (_tag != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tag Found!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('UID: ${_tag!.uid.join(', ')}'),
                          const SizedBox(height: 8),
                          Text('ATR: ${_tag!.atr.join(', ')}'),
                        ],
                      ),
                    ),
                  ),
                if (_error != null)
                  Text(
                    'Error: $_error',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
