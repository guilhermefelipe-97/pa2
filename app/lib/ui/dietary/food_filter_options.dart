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
    ];
