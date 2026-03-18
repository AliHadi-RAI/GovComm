import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../../services/dio_client.dart';
import '../../services/key_management_service.dart';
import '../home/conversations_screen.dart'; 
import '../home/chat_scaffold.dart'; 
import '../../services/socket_service.dart';

enum OtpPurpose { registration, login }

class OtpScreen extends StatefulWidget {
  final String email;
  final OtpPurpose purpose;
  final String? token;

  const OtpScreen({
    super.key,
    required this.email,
    required this.purpose,
    this.token,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _isLoading = false;

  Future<void> _verifyOtp() async {
    setState(() => _isLoading = true);
    try {
      final response = await DioClient().verifyOtp(widget.email, _otpController.text);

      if (!mounted) return; 

      if (widget.purpose == OtpPurpose.registration) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification successful! Please login.')),
        );
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        final String finalToken = response.data['token'];

        DioClient().setToken(finalToken);
        await _storage.write(key: 'jwt_token', value: finalToken);
        
        Map<String, dynamic> decodedToken = JwtDecoder.decode(finalToken);
        int userId = int.parse(decodedToken['id'].toString());
        
        final keyManager = KeyManagementService(sharedSignalService);
        await keyManager.ensureKeysPublished(userId);

        debugPrint("🌐 Tokens saved and keys published. Connecting Socket...");
        SocketService().connect(finalToken);
        
        if (!mounted) return;
        
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ConversationsScreen()),
          (route) => false,
        );
      }
    } on DioException catch (e) {
      String msg = 'Verification failed';
      if (e.response?.data != null) {
        if (e.response?.data is Map) {
          msg = e.response?.data['error'] ?? msg;
        } else {
          msg = e.response?.data.toString() ?? msg;
        }
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Identity')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 64, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              "Enter the 6-digit code sent to\n${widget.email}", 
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _otpController,
              decoration: const InputDecoration(
                labelText: 'OTP Code', 
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            const SizedBox(height: 24),
            _isLoading 
              ? const CircularProgressIndicator()
              : SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _verifyOtp, 
                    child: const Text('VERIFY & CONTINUE'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}