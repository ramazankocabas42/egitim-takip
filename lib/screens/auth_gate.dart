import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'profile_setup_screen.dart';

/// Oturum durumuna göre giriş, profil oluşturma ya da ana ekranı gösterir.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Loading());
        }
        final user = authSnap.data;
        if (user == null) return const LoginScreen();
        return _ProfileGate(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class _ProfileGate extends StatefulWidget {
  const _ProfileGate({super.key, required this.user});

  final User user;

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  late final Stream<AppUser?> _stream = Db.userStream(widget.user.uid);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(actions: const [LogoutButton()]),
            body: EmptyState(
                icon: Icons.error_outline, text: errorText(snap.error!)),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(body: Loading());
        }
        final me = snap.data;
        if (me == null) return ProfileSetupScreen(user: widget.user);
        return HomeScreen(key: ValueKey('${me.uid}|${me.role.name}'), me: me);
      },
    );
  }
}
