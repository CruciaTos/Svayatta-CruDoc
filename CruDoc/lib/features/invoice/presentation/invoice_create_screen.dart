import 'package:flutter/material.dart';

class InvoiceCreateScreen extends StatelessWidget {
  const InvoiceCreateScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Create Invoice'),
      ),
      body: const Center(
        child: Text(
          'Invoice creation coming soon',
          style: TextStyle(fontSize: 18, color: Colors.white70),
        ),
      ),
    );
  }
}