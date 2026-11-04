import 'package:flutter/material.dart';

const foodFilterOptions =
    <({String tag, String label, String detail, IconData icon})>[
      (
        tag: 'caseiro',
        label: 'Caseiro',
        detail: 'Refeições de estilo caseiro',
        icon: Icons.soup_kitchen_outlined,
      ),
      (
        tag: 'vegetariano',
        label: 'Vegetariano',
        detail: 'Opções sem carne',
        icon: Icons.eco_outlined,
      ),
      (
        tag: 'vegano',
        label: 'Vegano',
        detail: 'Opções sem origem animal',
        icon: Icons.spa_outlined,
      ),
      (
        tag: 'low-carb',
        label: 'Low-carb',
        detail: 'Opções com menos carboidratos',
        icon: Icons.egg_alt_outlined,
      ),
      (
        tag: 'integral',
        label: 'Integral',
        detail: 'Opções com ingredientes integrais',
        icon: Icons.grain_outlined,
      ),
      (
        tag: 'marmita',
        label: 'Marmita',
        detail: 'Refeição pronta em marmita',
        icon: Icons.lunch_dining_outlined,
      ),
      (
        tag: 'quentinha',
        label: 'Quentinha',
        detail: 'Quentinha para levar ou entregar',
        icon: Icons.takeout_dining_outlined,
      ),
      (
        tag: 'self-service',
        label: 'Self-service por quilo',
        detail: 'Bufê pago pelo peso do prato',
        icon: Icons.scale_outlined,
      ),
    ];

/// Texto curto da tag no formulário e na ficha: a própria tag, exceto
/// "self-service", que vira "self-service por quilo" (F30).
String foodTagLabel(String tag) =>
    tag == 'self-service' ? 'self-service por quilo' : tag;
