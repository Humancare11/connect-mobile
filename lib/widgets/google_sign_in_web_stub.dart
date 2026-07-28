import 'package:flutter/material.dart';

Widget renderButton() {
  return SizedBox(
    width: double.infinity,
    height: 54,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        ),
        child: const Center(
          child: Text(
            'Continue with Google',
            style: TextStyle(
              fontFamily: 'Satoshi',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
        ),
      ),
    ),
  );
}
