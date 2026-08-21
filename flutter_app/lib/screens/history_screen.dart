// history_screen.dart — "History" sidebar entry → Spectrum Memories
// screen: a curated timeline of ZX Spectrum milestones + the user's
// personal recent-plays list (from SharedPreferences).
//
// The Spectrum arrived in April 1982 at £125 for 16K and £175 for 48K,
// and did for British bedrooms what nothing else had: it was cheap
// enough to be a Christmas present and open enough that the people who
// got one started writing games on it. Most of the UK games industry
// came out of that.

import 'package:flutter/material.dart';

class _Milestone {
  final String year;
  final String title;
  final String detail;
  const _Milestone(this.year, this.title, this.detail);
}

/// The moments the Spectrum is remembered for. Curated, not exhaustive --
/// picked to span the machine's commercial life and the industry that grew
/// out of it.
const List<_Milestone> _kMilestones = [
  _Milestone('1982', 'The Spectrum arrives',
      'Sinclair Research launches the ZX Spectrum in April at 125 pounds '
          'for 16K, 175 for 48K. A rubber keyboard, a Z80A at 3.5MHz, and '
          'eight colours with the attribute clash that would define how '
          'Spectrum games look.'),
  _Milestone('1983', 'Bedroom coders become an industry',
      'Ultimate Play the Game releases Jetpac and sells hundreds of '
          'thousands of copies from a converted shop in Ashby. Written by '
          'two brothers; the studio later becomes Rare.'),
  _Milestone('1983', 'Manic Miner and the platform game',
      'Matthew Smith writes Manic Miner in six weeks. Twenty screens, an '
          'in-game tune played on the beeper while the game runs, and a '
          'design vocabulary the whole platform genre copies.'),
  _Milestone('1984', 'Isometric 3D on 48K',
      'Knight Lore ships with the Filmation engine and puts a convincing '
          '3D room on a machine with no hardware to do it. Reviewers '
          'describe it as making every other game look old overnight.'),
  _Milestone('1984', 'Elite and the open universe',
      'The Spectrum conversion of Elite fits eight galaxies of 256 '
          'planets into 48K by generating them from a seed rather than '
          'storing them -- procedural generation as a memory tactic.'),
  _Milestone('1986', 'The 128K and proper sound',
      'The ZX Spectrum 128 adds the AY-3-8912 sound chip, 128K of paged '
          'RAM and a numeric keypad. Games stop making do with the '
          'one-bit beeper.'),
  _Milestone('1987', 'Amstrad and the +2/+3',
      'Amstrad buys the Sinclair name and ships the +2 with a built-in '
          'tape deck, then the +3 with a 3-inch floppy drive. The '
          'Spectrum outlives Sinclair Research itself.'),
  _Milestone('1992', 'The end of the line',
      'Amstrad discontinues the Spectrum after a decade and roughly five '
          'million machines. The cassette-loading screech is, by then, a '
          'generation\'s shared memory.'),
  _Milestone('1996', 'Emulation keeps it alive',
      'Z80 and JPP arrive on PC, and the World of Spectrum archive begins '
          'collecting the library with publishers\' permission -- one of '
          'the earliest legitimate retro preservation efforts.'),
  _Milestone('2026', 'Retro-Spectrum',
      'This Flutter port: Linux, Android and iOS over the UnrealSpeccy '
          'Portable core, dart:ffi and a plain C bridge, with the ROMs '
          'bundled so there is nothing to hunt for.'),
];

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050607),
      appBar: AppBar(
        title: const Text('📜 Spectrum Memories', style: TextStyle(fontSize: 14)),
        toolbarHeight: 44,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _kMilestones.length,
        itemBuilder: (_, i) => _MilestoneRow(m: _kMilestones[i]),
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final _Milestone m;
  const _MilestoneRow({required this.m});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1A1F2C)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF3D8BFF),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(m.year,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(m.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 4),
        Text(m.detail,
            style: const TextStyle(
                color: Color(0xFFB9C2CE), fontSize: 11, height: 1.35)),
      ]),
    );
  }
}