import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../routing/routes.dart';
import 'dietary_filter_panel.dart';

class DietaryView extends StatelessWidget {
  const DietaryView({super.key});
  @override
  Widget build(BuildContext context) {
    void back() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.feed);
      }
    }

    return Scaffold(
      body: SafeArea(
        child: DietaryFilterPanel(onDone: back, onCancel: back),
      ),
    );
  }
}
