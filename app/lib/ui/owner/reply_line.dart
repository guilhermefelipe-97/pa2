import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/reputation_repository.dart';
import '../../domain/relative_time.dart';

class ReplyLine extends StatelessWidget {
  const ReplyLine({
    super.key,
    required this.reviewId,
    this.canReply = false,
    this.verifyOwner,
    this.framed = false,
  });
  final String reviewId;
  final bool canReply;
  final bool framed;
  final Future<bool> Function()? verifyOwner;
  @override
  Widget build(BuildContext context) {
    final repo = context.read<ReputationRepository?>();
    if (repo == null) return const SizedBox.shrink();
    final uid = context.watch<AuthRepository>().currentUserId;
    return _Reply(
      key: ValueKey('$uid-$reviewId'),
      repo: repo,
      reviewId: reviewId,
      uid: uid,
      canReply: canReply,
      verifyOwner: verifyOwner,
      framed: framed,
    );
  }
}

class _Reply extends StatefulWidget {
  const _Reply({
    super.key,
    required this.repo,
    required this.reviewId,
    required this.uid,
    required this.canReply,
    required this.framed,
    this.verifyOwner,
  });
  final ReputationRepository repo;
  final String reviewId;
  final String? uid;
  final bool canReply;
  final bool framed;
  final Future<bool> Function()? verifyOwner;
  @override
  State<_Reply> createState() => _ReplyState();
}

class _ReplyState extends State<_Reply> {
  OwnerReply? reply;
  bool busy = false, loaded = false;
  String? error;
  int _sequence = 0;
  bool authorized = true;
  String? get validation => text.text.trim().isEmpty
      ? 'Escreva uma resposta de 1 a 1000 caracteres.'
      : text.text.trim().length > 1000
      ? 'A resposta pode ter até 1000 caracteres.'
      : null;
  bool get current =>
      mounted && context.read<AuthRepository>().currentUserId == widget.uid;
  final text = TextEditingController();
  @override
  void initState() {
    super.initState();
    text.addListener(_textChanged);
    load();
  }

  void _textChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _Reply oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.canReply != widget.canReply) authorized = widget.canReply;
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final sequence = ++_sequence;
    try {
      final result = await widget.repo.replyFor(widget.reviewId);
      if (current && sequence == _sequence) {
        setState(() {
          reply = result ?? reply;
          loaded = true;
          error = null;
        });
      }
    } on Object {
      if (current && sequence == _sequence) {
        setState(() => error = 'Resposta indisponível. Tentar novamente');
      }
    }
  }

  Future<void> send() async {
    if (busy ||
        widget.uid == null ||
        validation != null ||
        !authorized ||
        !widget.canReply ||
        !current) {
      return;
    }
    ++_sequence;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.verifyOwner != null && !await widget.verifyOwner!()) {
        if (current) {
          setState(() {
            authorized = false;
            error =
                'Titularidade revogada. A resposta histórica continua disponível.';
          });
        }
        return;
      }
      if (!current) return;
      await widget.repo.reply(widget.uid!, widget.reviewId, text.text);
      if (current) await load();
    } on Object {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível responder. Confira titularidade e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (reply != null) ...[
        Container(
          width: double.infinity,
          margin: widget.framed
              ? const EdgeInsets.only(top: 12)
              : EdgeInsets.zero,
          padding: widget.framed ? const EdgeInsets.all(12) : EdgeInsets.zero,
          decoration: widget.framed
              ? BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resposta do estabelecimento · ${reply!.authorName} · ${relativeTime(reply!.createdAt, DateTime.now())}',
                style: widget.framed
                    ? Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      )
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                reply!.text,
                style: widget.framed
                    ? Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ] else if (loaded && widget.canReply && authorized) ...[
        const Text(
          'Uma resposta pública e imutável, de 1–1000 caracteres. Não altera as notas.',
        ),
        TextField(
          controller: text,
          enabled: !busy,
          maxLines: 4,
          maxLength: 1000,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          decoration: InputDecoration(
            labelText: 'Resposta do estabelecimento',
            errorText: text.text.isEmpty ? null : validation,
          ),
        ),
        TextButton(
          onPressed: busy || validation != null ? null : send,
          child: Text(busy ? 'Enviando…' : 'Responder uma vez'),
        ),
      ],
      if (!widget.framed || !loaded || widget.canReply)
        TextButton(
          onPressed: busy ? null : load,
          child: const Text('Atualizar resposta'),
        ),
      if (error != null)
        TextButton(onPressed: busy ? null : load, child: Text(error!)),
    ],
  );
}
