import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'model_management_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {},
        ),
        title: const Text('Academic Atelier'),
        actions: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.grey[300],
            child: const Icon(Icons.person, size: 18),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        children: [
          // AI Model Section
          _buildSectionHeader('AI Model'),
          _buildSettingTile(
            context,
            icon: Icons.memory,
            title: 'Model Management',
            subtitle: 'Download, delete, or re-download the AI model',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ModelManagementScreen(),
                ),
              );
            },
          ),
          
          const Divider(),
          
          // App Settings Section
          _buildSectionHeader('App Settings'),
          _buildSettingTile(
            context,
            icon: Icons.dark_mode,
            title: 'Dark Mode',
            subtitle: 'Toggle dark/light theme',
            trailing: Switch(
              value: false,
              onChanged: (value) {
                // TODO: Implement theme switching
              },
            ),
          ),
          _buildSettingTile(
            context,
            icon: Icons.notifications,
            title: 'Notifications',
            subtitle: 'Enable or disable notifications',
            trailing: Switch(
              value: true,
              onChanged: (value) {
                // TODO: Implement notifications
              },
            ),
          ),
          
          const Divider(),
          
          // About Section
          _buildSectionHeader('About'),
          _buildSettingTile(
            context,
            icon: Icons.info,
            title: 'About Academic Atelier',
            subtitle: 'Version 1.0.0',
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Academic Atelier',
                applicationVersion: '1.0.0',
                children: const [
                  Text(
                    'An AI-powered math problem solver that runs locally on your device.',
                  ),
                ],
              );
            },
          ),
          _buildSettingTile(
            context,
            icon: Icons.privacy_tip,
            title: 'Privacy Policy',
            subtitle: 'Read our privacy policy',
            onTap: () {
              // TODO: Open privacy policy
            },
          ),
          _buildSettingTile(
            context,
            icon: Icons.help,
            title: 'Help & Support',
            subtitle: 'Get help and contact support',
            onTap: () {
              // TODO: Open help
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.accentTeal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: AppColors.accentTeal,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary.withValues(alpha: 0.8),
        ),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
