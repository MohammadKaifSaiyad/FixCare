import 'package:flutter/material.dart';

/// Stub — replaced by Task 9 with the real address add/edit form.
class AddressFormScreen extends StatelessWidget {
  const AddressFormScreen({super.key, required this.addressId});
  final String? addressId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(addressId == null ? 'New address' : 'Edit address')),
        body: const Center(child: Text('Address form — coming in a later task')),
      );
}
