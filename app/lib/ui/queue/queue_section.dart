import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/owner_repository.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/location_service.dart';
import '../../data/repositories/place_repository.dart';
import '../../domain/models/place.dart';
import '../../domain/queue_status.dart';
import '../../domain/relative_time.dart';
import '../core/app_clock.dart';

class QueueSection extends StatelessWidget {
  const QueueSection({super.key, required this.place, this.compact = false});
  final Place place;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final repo = context.read<QueueRepository?>();
    if (repo == null) return const SizedBox.shrink();
    final uid = context.watch<AuthRepository>().currentUserId;
    if (uid == null) return const SizedBox.shrink();
    return _Queue(
      key: ValueKey('$uid-${place.id}'),
      repo: repo,
      uid: uid,
      place: place,
      compact: compact,
    );
  }
}

class _Queue extends StatefulWidget {
  const _Queue({
    super.key,
    required this.repo,
    required this.uid,
    required this.place,
    required this.compact,
  });
  final QueueRepository repo;
  final String uid;
  final Place place;
  final bool compact;
  @override
  State<_Queue> createState() => _QueueState();
}

class _QueueState extends State<_Queue> {
  List<QueueReport>? reports;
  String? error, notice;
  bool busy = false;
  final minutes = TextEditingController();
  Timer? timer;
  DateTime now() => context.read<AppClock?>()?.now() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    minutes.dispose();
    super.dispose();
  }

  int _loadSequence = 0;
  Future<void>? _read;
  bool loading = false;
  bool get current =>
      mounted && context.read<AuthRepository>().currentUserId == widget.uid;
  Future<void> load() {
    if (_read != null) return _read!;
    final run = _load();
    _read = run;
    return run.whenComplete(() => _read = null);
  }

  Future<void> _load() async {
    final sequence = ++_loadSequence;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final recovered = await widget.repo.reconcilePending(
        widget.uid,
        widget.place.id,
      );
      if (!current) return;
      if (recovered != null) _confirmed(recovered);
      final result = await widget.repo
          .fetchForPlace(
            widget.place.id,
            since: now().subtract(queueHistoryWindow),
          )
          .timeout(const Duration(seconds: 30));
      if (current && sequence == _loadSequence) {
        setState(() {
          reports = result;
          error = null;
        });
      }
    } on Object catch (e) {
      if (current && sequence == _loadSequence) {
        setState(
          () => error = e is QueueRecoveryRequired
              ? e.message
              : 'Não foi possível carregar a fila. Tentar novamente',
        );
      }
    } finally {
      if (current) setState(() => loading = false);
    }
  }

  void _confirmed(QueueReceipt receipt) {
    final place = widget.place;
    if (place.discovered) {
      final places = context.read<PlaceRepository?>();
      if (receipt.placeCreated) {
        places?.markPersisted(place);
      } else {
        places?.invalidate(place.id);
      }
    }
    setState(
      () => notice =
          '${receipt.recovered ? 'Envio anterior confirmado' : 'Relato identificado registrado'}: ${receipt.minutes} min.',
    );
  }

  Future<void> send() async {
    if (busy || loading || !current) return;
    final value = int.tryParse(minutes.text.trim());
    if (value == null || value < 0 || value > 180) {
      setState(() => notice = 'Informe uma espera inteira de 0 a 180 min.');
      return;
    }
    setState(() {
      busy = true;
      notice = null;
    });
    final locationService = context.read<LocationService>();
    final users = context.read<UserRepository>();
    try {
      final owner = await context
          .read<OwnerRepository>()
          .ownerOf(widget.place.id)
          .timeout(const Duration(seconds: 10));
      if (!current) return;
      if (owner == widget.uid) {
        throw StateError('O titular não relata o próprio local.');
      }
      final recovered = await widget.repo.reconcilePending(
        widget.uid,
        widget.place.id,
      );
      if (!current) return;
      if (recovered != null) {
        _confirmed(recovered);
        await load();
        if (!current ||
            now().isBefore(recovered.createdAt.add(queueCooldown))) {
          return;
        }
      }
      final last = await widget.repo
          .queueReportLockOf(widget.uid, widget.place.id)
          .timeout(const Duration(seconds: 10));
      if (!current) return;
      if (last != null && now().isBefore(last.add(queueCooldown))) {
        throw StateError('Aguarde 30 minutos entre relatos neste local.');
      }
      final location = await locationService.locate().timeout(
        const Duration(seconds: 20),
      );
      if (!current) return;
      final place = widget.place;
      if (location.position == null ||
          !place.hasCoordinates ||
          !nearForQueue(location.position!, (
            lat: place.lat!,
            lng: place.lng!,
          ))) {
        throw StateError(
          'Para relatar, esteja a até 150 m. A posição não é enviada.',
        );
      }
      final profile = await users
          .getProfile(widget.uid)
          .timeout(const Duration(seconds: 10));
      if (!current) return;
      if (profile == null) throw StateError('Perfil indisponível.');
      final receipt = await widget.repo.createReport(
        NewQueueReport(
          authorId: widget.uid,
          authorName: profile.displayName,
          placeId: place.id,
          minutes: value,
        ),
        newPlace: place.discovered ? place : null,
      );
      if (!current) return;
      _confirmed(receipt);
      await load();
    } on Object catch (e) {
      if (current) {
        setState(
          () => notice = e is QueueRecoveryRequired
              ? e.message
              : e is StateError
              ? e.message.toString()
              : 'Não foi possível registrar. Tente novamente; a trava será conferida antes de repetir.',
        );
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final at = now();
    final live = liveQueue(reports ?? [], at);
    final history = historicalQueue(reports ?? [], at);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Fila', style: Theme.of(context).textTheme.titleMedium),
        if (reports == null && error == null) const CircularProgressIndicator(),
        if (reports != null) ...[
          Text(
            live == null
                ? 'Sem sinal recente de fila'
                : 'Ao vivo: mediana ${live.median.toStringAsFixed(0)} min · ${live.count} pessoas · último relato há ${at.difference(live.latest).inMinutes} min',
          ),
          Text(
            history == null
                ? 'Histórico: amostra insuficiente (mínimo 3 pessoas).'
                : 'Histórico — faixa típica: ${history.p25!.toStringAsFixed(0)}–${history.p75!.toStringAsFixed(0)} min · ${history.count} pessoas',
          ),
          const Text(
            'Últimos 28 dias, mesmo dia da semana e faixa de 2 h (UTC−3). Uma espera por pessoa; sem estimativa quando os relatos são insuficientes.',
          ),
        ],
        TextButton(
          onPressed: loading || busy ? null : load,
          child: Text(loading ? 'Atualizando fila…' : 'Atualizar fila'),
        ),
        if (error != null)
          TextButton(
            onPressed: loading || busy ? null : load,
            child: Text(error!),
          ),
        const Text(
          'Relato público com seu nome. Até 150 m; posição usada só no aparelho.',
        ),
        TextField(
          controller: minutes,
          enabled: !busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Espera observada (0–180 min)',
          ),
        ),
        TextButton(
          onPressed: busy || loading ? null : send,
          child: Text(busy ? 'Enviando…' : 'Relatar espera'),
        ),
        if (notice != null) Text(notice!),
      ],
    );
    if (!widget.compact) return content;
    final estimate = live ?? history;
    String duration(double value) => value.round().toString();
    final range = estimate == null
        ? null
        : estimate.p25 == estimate.p75
        ? duration(estimate.median)
        : '${duration(estimate.p25!)}–${duration(estimate.p75!)}';
    return Card(
      margin: const EdgeInsets.only(top: 16),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ExpansionTile(
        key: const Key('place-queue-summary'),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          Icons.schedule,
          color: Theme.of(context).colorScheme.secondary,
        ),
        title: Text(
          range == null
              ? 'Fila estimada: sem dados recentes'
              : 'Fila estimada: $range min',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          error != null
              ? 'Não foi possível atualizar a fila'
              : loading && reports == null
              ? 'Carregando relatos…'
              : estimate == null
              ? 'Toque para informar uma espera'
              : '${live == null ? 'Histórico' : 'Atualizado'} ${relativeTime(estimate.latest, at)} · ${estimate.count} pessoa${estimate.count == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [content],
      ),
    );
  }
}
