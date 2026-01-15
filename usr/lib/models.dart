enum PokemonType {
  pikachu, // 快速，低伤 (Fast, Low Dmg)
  charmander, // 慢速，高伤 (Slow, High Dmg)
  bulbasaur, // 中等 (Medium)
}

class GameConfig {
  static const double enemySpeed = 100.0; // pixels per second
  static const int startingMoney = 150;
  static const int startingLives = 10;
}

class Enemy {
  String id;
  double progress; // 0.0 to 1.0 along the path
  int pathIndex; // Current segment of the path
  double x;
  double y;
  double hp;
  double maxHp;
  double speed;
  bool frozen; // Effect from Bulbasaur? (Future feature)

  Enemy({
    required this.id,
    this.progress = 0,
    this.pathIndex = 0,
    this.x = 0,
    this.y = 0,
    this.hp = 100,
    this.maxHp = 100,
    this.speed = 1.0,
    this.frozen = false,
  });
}

class Tower {
  String id;
  double x;
  double y;
  PokemonType type;
  double range;
  double damage;
  double cooldown; // Seconds
  double timeSinceLastShot;

  Tower({
    required this.id,
    required this.x,
    required this.y,
    required this.type,
  }) : timeSinceLastShot = 0,
       range = _getRange(type),
       damage = _getDamage(type),
       cooldown = _getCooldown(type);

  static double _getRange(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return 120;
      case PokemonType.charmander: return 150;
      case PokemonType.bulbasaur: return 100;
    }
  }

  static double _getDamage(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return 15;
      case PokemonType.charmander: return 40;
      case PokemonType.bulbasaur: return 25;
    }
  }

  static double _getCooldown(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return 0.5; // Fast
      case PokemonType.charmander: return 1.5; // Slow
      case PokemonType.bulbasaur: return 1.0; // Medium
    }
  }
  
  static int getCost(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return 50;
      case PokemonType.charmander: return 100;
      case PokemonType.bulbasaur: return 75;
    }
  }
  
  static String getName(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return "皮卡丘";
      case PokemonType.charmander: return "小火龙";
      case PokemonType.bulbasaur: return "妙蛙种子";
    }
  }
}

class Projectile {
  String id;
  double x;
  double y;
  double targetX;
  double targetY;
  double speed;
  double damage;
  String targetEnemyId;
  PokemonType type;
  bool active;

  Projectile({
    required this.id,
    required this.x,
    required this.y,
    required this.targetX,
    required this.targetY,
    required this.damage,
    required this.targetEnemyId,
    required this.type,
    this.speed = 400,
    this.active = true,
  });
}
