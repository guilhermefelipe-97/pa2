import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/profile_media_repository.dart';

class ProfileMediaImage extends StatefulWidget {
  const ProfileMediaImage({
    super.key,
    required this.uid,
    required this.kind,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });
  final String uid, kind;
  final Widget placeholder;
  final BoxFit fit;
  @override
  State<ProfileMediaImage> createState() => _ProfileMediaImageState();
}

class _ProfileMediaImageState extends State<ProfileMediaImage> {
  ProfileMediaRepository? repo;
  Uint8List? bytes;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final found = context.read<ProfileMediaRepository?>();
    if (found != repo) {
      repo?.removeListener(load);
      repo = found;
      repo?.addListener(load);
      load();
    }
  }

  @override
  void didUpdateWidget(covariant ProfileMediaImage old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid || old.kind != widget.kind) {
      bytes = null;
      load();
    }
  }

  Future<void> load() async {
    final seq = ++generation;
    try {
      final result = await repo?.get(widget.uid, widget.kind);
      if (mounted && seq == generation) setState(() => bytes = result);
    } on Object {
      if (mounted && seq == generation) setState(() => bytes = null);
    }
  }

  @override
  void dispose() {
    repo?.removeListener(load);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => bytes == null
      ? widget.placeholder
      : Image.memory(
          bytes!,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => widget.placeholder,
        );
}
