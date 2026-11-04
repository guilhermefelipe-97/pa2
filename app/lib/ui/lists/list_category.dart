import 'package:flutter/material.dart';

const listCategories = <({String? value, String label, IconData icon})>[
  (value: null, label: 'Geral', icon: Icons.bookmarks_outlined),
  (value: '☕', label: 'Cafés', icon: Icons.local_cafe_outlined),
  (value: '🍕', label: 'Pizzarias', icon: Icons.local_pizza_outlined),
  (value: '🍔', label: 'Hamburguerias', icon: Icons.lunch_dining_outlined),
  (value: '🍣', label: 'Japonesa', icon: Icons.ramen_dining_outlined),
  (value: '🍻', label: 'Bares', icon: Icons.sports_bar_outlined),
  (value: '🍰', label: 'Doces', icon: Icons.cake_outlined),
  (value: '🌮', label: 'Restaurantes', icon: Icons.restaurant_outlined),
  (value: '🌊', label: 'Passeios', icon: Icons.beach_access_outlined),
  (value: '💑', label: 'Encontros', icon: Icons.favorite_border),
  (value: '👯', label: 'Amigos', icon: Icons.people_outline),
  (value: '🎉', label: 'Comemorações', icon: Icons.celebration_outlined),
  (value: '⭐', label: 'Favoritos', icon: Icons.star_border),
];

IconData listCategoryIcon(String? value) => listCategories
    .firstWhere((c) => c.value == value, orElse: () => listCategories.first)
    .icon;
