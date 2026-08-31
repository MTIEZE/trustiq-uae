import 'package:flutter/material.dart';

import '../data/service_status.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/brand.dart';

/// What somebody sees when the service has been stopped, or their build has.
///
/// This is the screen the remote switch exists to show, so it has one job: say
/// what is happening in a way that does not read as a crash. Two things make
/// the difference. It carries the mark, because a branded page is obviously a
/// decision somebody took and a blank error page is obviously a failure. And it
/// says what is safe: nothing already agreed can change while the service is
/// paused, and nobody's documents are going anywhere.
///
/// The wording can come from status.json, in the reader's language, so an
/// actual incident can say what is wrong and when it ends. The strings here are
/// the fallback for when it says nothing.
class HeldScreen extends StatelessWidget {
  const HeldScreen({super.key, required this.gate});

  final ServiceStatusGate gate;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = L.of(context);
    // Read here rather than passed in. The caller is _home(), whose `context`
    // is the one above MaterialApp, where there is no Localizations to ask;
    // this one is inside it. That mistake threw only on the path where the
    // service is actually held, which is the path nobody exercises by hand.
    final languageCode = Localizations.localeOf(context).languageCode;

    final outdated = gate.outdated;
    final notice = gate.status.notice(languageCode);

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TrustIqMark(size: IconSize.hero),
                  const SizedBox(height: Space.xl),
                  Text(
                    outdated ? l.heldOutdatedTitle : l.heldPausedTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    outdated ? l.heldOutdatedBody : l.heldPausedBody,
                    style: TextStyle(color: c.inkSoft, height: 1.5),
                  ),

                  // Whatever the file had to say, if it said anything. Below
                  // the app's own sentence rather than instead of it: an
                  // incident note explains this incident, and the sentence
                  // above is the part that is always true.
                  if (notice.isNotEmpty) ...[
                    const SizedBox(height: Space.lg),
                    Container(
                      padding: const EdgeInsets.all(Space.md),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: c.rule),
                      ),
                      child: Text(notice, style: TextStyle(color: c.ink, height: 1.5)),
                    ),
                  ],

                  const SizedBox(height: Space.xl),

                  // Offered even when the build is too old, where it cannot
                  // help. Taking it away would mean somebody who has just
                  // updated has no way to find out, short of guessing that
                  // killing the app is the answer.
                  FilledButton(
                    onPressed: gate.checking ? null : gate.check,
                    child: Text(gate.checking ? l.heldChecking : l.heldRetry),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
