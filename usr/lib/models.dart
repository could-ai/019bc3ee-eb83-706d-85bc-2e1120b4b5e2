enum PokemonType {
  pikachu, // Fast, Low Dmg
  charmander, // Slow, High Dmg
  bulbasaur, // Medium
  squirtle, // New: Water type, medium range
  eevee, // New: Fast and cheap
}

class GameConfig {
  static const double enemySpeed = 100.0;
  static const int startingMoney = 150;
  static const int startingLives = 10;
}

class Enemy {
  String id;
  double progress;
  int pathIndex;
  double x;
  double y;
  double hp;
  double maxHp;
  double speed;
  bool frozen;
  PokemonType type; // Added for variety

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
    this.type = PokemonType.pikachu,
  });
}

class Tower {
  String id;
  double x;
  double y;
  PokemonType type;
  double range;
  double damage;
  double cooldown;
  double timeSinceLastShot;
  int level; // Added for upgrading

  Tower({
    required this.id,
    required this.x,
    required this.y,
    required this.type,
  }) : timeSinceLastShot = 0,
       range = _getRange(type),
       damage = _getDamage(type),
       cooldown = _getCooldown(type),
       level = 1;

  static double _getRange(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return 120;
      case PokemonType.charmander: return 150;
      case PokemonType.bulbasaur: return 100;
      case PokemonType.squirtle: return 130;
      case PokemonType.eevee: return 110;
    }
  }

  static double _getDamage(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return 15;
      case PokemonType.charmander: return 40;
      case PokemonType.bulbasaur: return 25;
      case PokemonType.squirtle: return 30;
      case PokemonType.eevee: return 12;
    }
  }

  static double _getCooldown(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return 0.5;
      case PokemonType.charmander: return 1.5;
      case PokemonType.bulbasaur: return 1.0;
      case PokemonType.squirtle: return 1.2;
      case PokemonType.eevee: return 0.4;
    }
  }
  
  static int getCost(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return 50;
      case PokemonType.charmander: return 100;
      case PokemonType.bulbasaur: return 75;
      case PokemonType.squirtle: return 85;
      case PokemonType.eevee: return 40;
    }
  }
  
  static String getName(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return "皮卡丘";
      case PokemonType.charmander: return "小火龙";
      case PokemonType.bulbasaur: return "妙蛙种子";
      case PokemonType.squirtle: return "杰尼龟";
      case PokemonType.eevee: return "伊布";
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

class GoldDrop {
  double x;
  double y;
  int amount;
  double opacity;

  GoldDrop({
    required this.x,
    required this.y,
    required this.amount,
    this.opacity = 1.0,
  });
}
