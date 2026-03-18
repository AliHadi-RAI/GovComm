import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../services/dio_client.dart';
import 'register_screen.dart'; 
import 'otp_screen.dart';
import 'dart:math' as math;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoading = false;
  bool _obscurePassword = true;

  bool _isValidGovEmail(String email) {
    return email.endsWith('@gov.qa');
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await DioClient().login(
        _emailController.text,
        _passwordController.text,
      );

      final token = response.data['token'];

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              email: _emailController.text,
              purpose: OtpPurpose.login,
              token: token,
            ),
          ),
        );
      }
    } on DioException catch (e) {
      String errorMessage = 'Login failed';
      if (e.response != null && e.response!.data != null) {
        errorMessage = e.response!.data['error'] ?? errorMessage;
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => RegisterScreen()),
    );
  }

  @override
    Widget build(BuildContext context) {
      final Color darkBlue = Colors.blue.shade900;

      return Scaffold(
        backgroundColor: Colors.white, 
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0.0, constraints.maxHeight - 48.0), 
                  ),
                  child: IntrinsicHeight(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch, 
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 80, 
                                height: 80,
                                child: Image.asset(
                                  'assets/logo.jpeg',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(Icons.security, size: 64, color: darkBlue);
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'govcomm',
                                style: TextStyle(
                                  fontSize: 44, 
                                  fontWeight: FontWeight.bold,
                                  color: darkBlue, 
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          
                          Align(
                            alignment: Alignment.center, 
                            child: Text(
                              'Secure Messaging for Government',
                              style: TextStyle(
                                fontSize: 16,
                                color: darkBlue, 
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 80),
                          _buildMinimalTextField(
                            controller: _emailController,
                            label: 'Government Email',
                            icon: Icons.alternate_email,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Email required';
                              if (!_isValidGovEmail(value)) return 'Must be @gov.qa email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildMinimalTextField(
                            controller: _passwordController,
                            label: 'Password',
                            icon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                color: Colors.grey,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Password required';
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 48),
                          
                          _isLoading 
                            ? Center(
                                child: CircularProgressIndicator(
                                  color: darkBlue,
                                  strokeWidth: 2,
                                ),
                              )
                            : SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  onPressed: _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: darkBlue, 
                                    foregroundColor: Colors.white, 
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text(
                                    'Log In',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                          
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _navigateToRegister,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white, 
                                foregroundColor: darkBlue, 
                                elevation: 0,
                                side: BorderSide(color: darkBlue, width: 1.5), 
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                "Create Account",
                                style: TextStyle(
                                  fontSize: 15, 
                                  fontWeight: FontWeight.w600
                                ),
                              ),
                            ),
                          ),

                          const Spacer(), 

                          const Divider(
                            color: Colors.black26,
                            thickness: 1,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildImageLogoPlaceholder(''), // Add asset address here 
                              
                              Container(height: 35, width: 1, color: Colors.grey.shade400),
                              
                              _buildImageLogoPlaceholder(''), 
                              
                              Container(height: 35, width: 1, color: Colors.grey.shade400),
                              
                              _buildImageLogoPlaceholder(''), 
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
          ),
        ),
      );
    }

    Widget _buildImageLogoPlaceholder(String assetPath) {
      return SizedBox(
        width: 50,
        height: 50,
        child: assetPath.isNotEmpty
            ? Image.asset(assetPath, fit: BoxFit.contain)
            : Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
      );
    }

    Widget _buildMinimalTextField({
      required TextEditingController controller,
      required String label,
      required IconData icon,
      bool obscureText = false,
      TextInputType? keyboardType,
      String? Function(String?)? validator,
      Widget? suffixIcon,
    }) {
      final Color darkBlue = Colors.blue.shade900;

      return TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.black87, fontSize: 15), 
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black45),
          prefixIcon: Icon(icon, color: darkBlue, size: 20),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white, 
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.blue.shade200, width: 1.5), 
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.blue.shade200, width: 1.5), 
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: darkBlue, width: 2.5), 
          ),
          errorStyle: const TextStyle(color: Colors.redAccent),
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
        validator: validator,
      );
    }
}