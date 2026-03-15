import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import '../../../core/constants/constants.dart';

class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Vault'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildStatsCard(),
            const SizedBox(height: 32),
            _buildNoteCard('Project Alpha', 'Secure keys for the next release...', '10 Min Ago'),
            const SizedBox(height: 16),
            _buildNoteCard('Investment Strategy', 'Diversify into tech and real estate...', '2 Hours Ago'),
            const SizedBox(height: 16),
            _buildNoteCard('Dream Journal', 'Flying over a city made of glass...', 'Yesterday'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return FadeInDown(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: AppColors.premiumGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            const Icon(Icons.security_rounded, color: Colors.white, size: 40),
            const SizedBox(height: 16),
            const Text(
              'Encryption Active',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const Text(
              '3 Private items synchronized',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteCard(String title, String content, String time) {
    return FadeInUp(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const Icon(Icons.more_vert_rounded, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(content, style: const TextStyle(color: AppColors.textBody)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textBody),
                const SizedBox(width: 4),
                Text(time, style: const TextStyle(color: AppColors.textBody, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
