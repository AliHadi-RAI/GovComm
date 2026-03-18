import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../services/dio_client.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  bool _isValidGovEmail(String email) {
    return email.endsWith('@gov.qa');
  }

    Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      await DioClient().register(
        _usernameController.text, 
        _emailController.text, 
        _passwordController.text
      );
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              email: _emailController.text,
              purpose: OtpPurpose.registration,
            ),
          ),
        );
      }
    } on DioException catch (e) {
      String err = 'Registration failed';
      if (e.response != null && e.response!.data != null) {
        err = e.response!.data['error'] ?? err;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('GovComm Registration')),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: 'Username'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Government Email'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  if (!_isValidGovEmail(value)) return 'Must be @gov.qa or @gov.ae';
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => v!.length < 6 ? 'Min 6 chars' : null,
              ),
              SizedBox(height: 24),
              _isLoading 
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _handleRegister,
                    child: Text('REGISTER'),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}