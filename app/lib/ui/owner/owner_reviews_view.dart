import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/owner_repository.dart';
import '../../data/repositories/reputation_repository.dart';
import '../../domain/models/review.dart';
import '../feed/widgets/review_tile.dart';
import 'reply_line.dart';

class OwnerReviewsView extends StatelessWidget {
  const OwnerReviewsView({super.key, required this.placeId});
  final String placeId;
  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthRepository>().currentUserId;
    return Scaffold(
      appBar: AppBar(title: const Text('Avaliações e respostas')),
      body: uid == null
          ? const SizedBox.shrink()
          : _Reviews(
              key: ValueKey('$uid-$placeId'),
              uid: uid,
              placeId: placeId,
            ),
    );
  }
}

class _Reviews extends StatefulWidget {
  const _Reviews({super.key, required this.uid, required this.placeId});
  final String uid, placeId;
  @override
  State<_Reviews> createState() => _ReviewsState();
}

class _ReviewsState extends State<_Reviews> with WidgetsBindingObserver {
  final reviews = <Review>[];
  String? next, error;
  bool busy = false, loaded = false, owned = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  bool _wasCurrent = true;
  int _ownerSequence = 0;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && !_wasCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) revalidate();
      });
    }
    _wasCurrent = current;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) revalidate();
  }

  Future<bool> revalidate() async {
    final sequence = ++_ownerSequence;
    final repository = context.read<OwnerRepository>();
    setState(() => owned = false);
    try {
      final owner = await repository
          .ownerOf(widget.placeId)
          .timeout(const Duration(seconds: 10));
      if (!mounted || sequence != _ownerSequence) return false;
      final value = owner == widget.uid;
      setState(() {
        owned = value;
        error = value ? null : 'Titularidade atual necessária para responder.';
      });
      return value;
    } on Object {
      if (mounted && sequence == _ownerSequence) {
        setState(() {
          owned = false;
          error = 'Titularidade indisponível. Tentar novamente';
        });
      }
      return false;
    }
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await revalidate()) return;
      if (!mounted) return;
      final page = await context.read<ReputationRepository>().reviewsForPlace(
        widget.placeId,
        after: next,
      );
      if (!mounted) return;
      setState(() {
        reviews.addAll(page.reviews);
        next = page.next;
        loaded = true;
      });
    } on Object {
      if (mounted) {
        setState(() => error = 'Não foi possível carregar. Tentar novamente');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: reviews.length + 2,
    itemBuilder: (context, index) {
      if (index == 0) {
        return TextButton(
          onPressed: busy
              ? null
              : () async {
                  if (await revalidate() && mounted) {
                    setState(() {
                      reviews.clear();
                      next = null;
                      loaded = false;
                    });
                    await load();
                  }
                },
          child: const Text('Atualizar avaliações e titularidade'),
        );
      }
      if (index <= reviews.length) {
        final review = reviews[index - 1];
        return Column(
          key: ValueKey('owner-review-${review.id}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReviewTile(review: review, now: DateTime.now()),
            ReplyLine(
              reviewId: review.id,
              canReply: owned,
              verifyOwner: revalidate,
            ),
            const Divider(),
          ],
        );
      }
      return Column(
        children: [
          if (loaded && reviews.isEmpty)
            const Text('Nenhuma avaliação neste local.'),
          if (busy) const Center(child: CircularProgressIndicator()),
          if (!busy && (next != null || !loaded || error != null))
            TextButton(onPressed: load, child: Text(error ?? 'Carregar mais')),
        ],
      );
    },
  );
}
