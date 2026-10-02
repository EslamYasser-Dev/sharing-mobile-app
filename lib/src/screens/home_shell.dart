import 'package:flutter/material.dart';

import '../theme.dart';
import 'account_screen.dart';
import 'files_screen.dart';
import 'p2p_screen.dart';
import 'shares_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  late final List<Widget> _screens = [
    FilesScreen(onOpenShares: () => setState(() => _index = 1)),
    const SharesScreen(),
    const P2PScreen(),
    const AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final pal = SfsPalette.of(context);
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      // Hairline rule above the bar, the way the landing separates its
      // header from the page.
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: pal.rule)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              label: 'Files',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.link), label: 'Shares'),
            BottomNavigationBarItem(
              icon: Icon(Icons.devices_other),
              label: 'Direct',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
