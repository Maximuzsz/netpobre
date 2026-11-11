import 'package:flutter/material.dart';

import '../models/jellyfin_session.dart';
import '../theme.dart';
import '../widgets/app_update_dialog.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.profiles,
    required this.onSelected,
    required this.onAdd,
    required this.onRemove,
  });

  final List<JellyfinSession> profiles;
  final ValueChanged<JellyfinSession> onSelected;
  final VoidCallback onAdd;
  final ValueChanged<JellyfinSession> onRemove;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const CasaFlixMark(size: 30)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Text(
                  'Quem está assistindo?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final profile in profiles)
                      _ProfileCard(
                        profile: profile,
                        onTap: () => onSelected(profile),
                        onRemove: () => onRemove(profile),
                      ),
                    _AddProfileCard(onTap: onAdd),
                  ],
                ),
                const SizedBox(height: 38),
                OutlinedButton.icon(
                  onPressed: () => AppUpdateDialog.show(context),
                  icon: const Icon(Icons.system_update_alt_rounded),
                  label: const Text('Verificar atualizações'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onTap,
    required this.onRemove,
  });

  final JellyfinSession profile;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        children: [
          InkWell(
            autofocus: true,
            onTap: onTap,
            onLongPress: onRemove,
            borderRadius: BorderRadius.circular(24),
            child: Ink(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: CasaFlixColors.ink,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(
                child: Text(
                  profile.userName.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: CasaFlixColors.sky,
                    fontSize: 58,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            profile.userName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Ink(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white30),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.add_rounded, size: 52),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Adicionar',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
