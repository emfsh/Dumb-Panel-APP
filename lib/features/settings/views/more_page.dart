import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16,
          left: 20,
          right: 20,
          bottom: 100,
        ),
        children: [
          const Text(
            '设置',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),

          // User Card
          if (user != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : AppColors.slate900,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isLight ? AppColors.slate200 : AppColors.slate800,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        user.username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.username,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.role.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          color: isLight
                              ? AppColors.slate500
                              : AppColors.slate400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),

          // App Settings Section
          _SectionLabel('应用设置'),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.dns_outlined,
            title: '服务器管理',
            isLight: isLight,
            onTap: () => context.push('/server-config?manage=1'),
          ),
          _SettingsItem(
            icon: Icons.key_outlined,
            title: '环境变量',
            isLight: isLight,
            onTap: () => context.go('/envs'),
          ),
          _SettingsItem(
            icon: Icons.notifications_none,
            title: '消息通知',
            isLight: isLight,
            onTap: () => context.push('/notifications'),
          ),
          _SettingsItem(
            icon: Icons.lock_outline,
            title: '应用锁',
            isLight: isLight,
            onTap: () => context.push('/app-lock'),
          ),

          if (user != null && user.isAdmin) ...[
            const SizedBox(height: 24),
            _SectionLabel('系统管理'),
            const SizedBox(height: 8),
            _SettingsItem(
              icon: Icons.code,
              title: '脚本管理',
              isLight: isLight,
              onTap: () => context.push('/scripts'),
            ),
            _SettingsItem(
              icon: Icons.sync,
              title: '订阅管理',
              isLight: isLight,
              onTap: () => context.push('/subscriptions'),
            ),
            _SettingsItem(
              icon: Icons.inventory_2_outlined,
              title: '依赖管理',
              isLight: isLight,
              onTap: () => context.push('/deps'),
            ),
            _SettingsItem(
              icon: Icons.people_outline,
              title: '用户管理',
              isLight: isLight,
              onTap: () => context.push('/users'),
            ),
            _SettingsItem(
              icon: Icons.security,
              title: '安全设置',
              isLight: isLight,
              onTap: () => context.push('/security'),
            ),
            _SettingsItem(
              icon: Icons.settings,
              title: '系统设置',
              isLight: isLight,
              onTap: () => context.push('/system-settings'),
            ),
            _SettingsItem(
              icon: Icons.api,
              title: 'Open API',
              isLight: isLight,
              onTap: () => context.push('/open-api'),
            ),
          ],

          const SizedBox(height: 24),
          _SectionLabel('其他'),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.volunteer_activism_outlined,
            title: '赞助名单',
            isLight: isLight,
            onTap: () => context.push('/sponsors'),
          ),
          _SettingsItem(
            icon: Icons.info_outline,
            title: '关于',
            isLight: isLight,
            onTap: () => _showAboutDialog(context),
          ),

          // Logout
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => _logout(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isLight
                    ? AppColors.red50
                    : AppColors.red500.withAlpha(12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isLight
                      ? AppColors.red500.withAlpha(50)
                      : AppColors.red500.withAlpha(40),
                ),
              ),
              child: const Center(
                child: Text(
                  '退出登录',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.red500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    child: const Text('取消'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogCtx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.red500,
                    ),
                    child: const Text('退出'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(authProvider.notifier).logout();
      if (context.mounted) {
        context.go('/server-config?manual=1');
      }
    }
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final packageInfoFuture = PackageInfo.fromPlatform();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('关于'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.dashboard_customize_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '呆呆面板',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FutureBuilder<PackageInfo>(
                        future: packageInfoFuture,
                        builder: (context, snapshot) {
                          final info = snapshot.data;
                          final versionLabel = info == null
                              ? '版本 -'
                              : '版本 ${info.version}${info.buildNumber.trim().isEmpty ? '' : '+${info.buildNumber}'}';
                          return Text(
                            versionLabel,
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '轻量级定时任务管理平台',
              style: TextStyle(
                fontSize: 13,
                color: isLight ? AppColors.slate600 : AppColors.slate300,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('知道了'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isLight;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.isLight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : AppColors.slate900,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLight ? AppColors.slate200 : AppColors.slate800,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isLight ? AppColors.slate500 : AppColors.slate400,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: isLight ? AppColors.slate400 : AppColors.slate600,
            ),
          ],
        ),
      ),
    );
  }
}
