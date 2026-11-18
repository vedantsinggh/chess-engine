import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// BOT DEFINITIONS
// ─────────────────────────────────────────────

enum BotDifficulty {
  beginner,
  casual,
  intermediate,
  advanced,
  master,
  grandmaster,
}

class BotProfile {
  final String id;
  final String name;
  final String title;
  final String description;
  final BotDifficulty difficulty;
  final IconData icon;
  final Color accentColor;
  final int eloRating;
  final int engineDepth;
  final double errorRate;

  const BotProfile({
    required this.id,
    required this.name,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.icon,
    required this.accentColor,
    required this.eloRating,
    required this.engineDepth,
    required this.errorRate,
  });
}

const List<BotProfile> kBotProfiles = [
  BotProfile(
    id: 'max',
    name: 'Max Strength',
    title: 'GM',
    description: 'The engine with no strength limit',
    difficulty: BotDifficulty.grandmaster,
    icon: Icons.psychology_rounded,
    accentColor: Color(0xFF10B981),
    eloRating: 3500,
    engineDepth: 20,
    errorRate: 0.0,
  ),
  BotProfile(
    id: 'master',
    name: 'Master',
    title: 'Expert',
    description: 'Strong opponent for advanced players',
    difficulty: BotDifficulty.master,
    icon: Icons.emoji_events_rounded,
    accentColor: Color(0xFFF59E0B),
    eloRating: 2200,
    engineDepth: 14,
    errorRate: 0.1,
  ),
  BotProfile(
    id: 'advanced',
    name: 'Advanced',
    title: 'Hard',
    description: 'Challenging for club-level players',
    difficulty: BotDifficulty.advanced,
    icon: Icons.trending_up_rounded,
    accentColor: Color(0xFFEF4444),
    eloRating: 1800,
    engineDepth: 10,
    errorRate: 0.2,
  ),
  BotProfile(
    id: 'intermediate',
    name: 'Intermediate',
    title: 'Medium',
    description: 'Good for casual players',
    difficulty: BotDifficulty.intermediate,
    icon: Icons.equalizer_rounded,
    accentColor: Color(0xFF8B5CF6),
    eloRating: 1400,
    engineDepth: 6,
    errorRate: 0.3,
  ),
  BotProfile(
    id: 'casual',
    name: 'Casual',
    title: 'Easy',
    description: 'Perfect for beginners',
    difficulty: BotDifficulty.casual,
    icon: Icons.spa_rounded,
    accentColor: Color(0xFF06B6D4),
    eloRating: 1000,
    engineDepth: 4,
    errorRate: 0.4,
  ),
  BotProfile(
    id: 'beginner',
    name: 'Beginner',
    title: 'Very Easy',
    description: 'Learn the basics comfortably',
    difficulty: BotDifficulty.beginner,
    icon: Icons.child_care_rounded,
    accentColor: Color(0xFFEC4899),
    eloRating: 600,
    engineDepth: 2,
    errorRate: 0.6,
  ),
];

/// Profile with [id], or null.
BotProfile? botProfileById(String? id) {
  for (final b in kBotProfiles) {
    if (b.id == id) return b;
  }
  return null;
}
