import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'models.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  // Game State
  late Ticker _ticker;
  double _lastTime = 0;
  
  int _money = GameConfig.startingMoney;
  int _lives = GameConfig.startingLives;
  int _wave = 1;
  bool _gameOver = false;
  
  // Entities
  List<Enemy> _enemies = [];
  List<Tower> _towers = [];
  List<Projectile> _projectiles = [];
  
  // Wave Management
  Timer? _waveTimer;
  int _enemiesSpawnedInWave = 0;
  
  // UI State
  PokemonType? _selectedTowerType;

  // Path Definition (Normalized 0.0 to 1.0)
  final List<Offset> _pathPoints = [
    const Offset(0.0, 0.2),
    const Offset(0.8, 0.2),
    const Offset(0.8, 0.5),
    const Offset(0.2, 0.5),
    const Offset(0.2, 0.8),
    const Offset(1.0, 0.8),
  ];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_gameLoop);
    _ticker.start();
    _startWave();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _waveTimer?.cancel();
    super.dispose();
  }

  void _startWave() {
    _enemiesSpawnedInWave = 0;
    _waveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_gameOver) {
        timer.cancel();
        return;
      }
      
      if (_enemiesSpawnedInWave < _wave * 5) {
        _spawnEnemy();
        _enemiesSpawnedInWave++;
      } else {
        timer.cancel();
        // Wait for all enemies to die before next wave? 
        // For simplicity, we just auto-start next wave after a delay if desired, 
        // but here we'll let the user trigger or just wait.
        // Let's auto-increment wave logic in game loop if list is empty.
      }
    });
  }

  void _spawnEnemy() {
    setState(() {
      // Increase HP with waves
      double hp = 100.0 + (_wave * 20);
      _enemies.add(Enemy(
        id: DateTime.now().toString() + Random().nextInt(1000).toString(),
        maxHp: hp,
        hp: hp,
        speed: 0.1 + (_wave * 0.01), // Slightly faster each wave
      ));
    });
  }

  void _gameLoop(Duration elapsed) {
    if (_gameOver) return;

    double currentTime = elapsed.inMilliseconds / 1000.0;
    double dt = currentTime - _lastTime;
    _lastTime = currentTime;

    if (dt > 0.1) dt = 0.1; // Cap delta time to prevent huge jumps

    setState(() {
      Size screenSize = MediaQuery.of(context).size;
      
      // 1. Update Enemies
      for (int i = _enemies.length - 1; i >= 0; i--) {
        Enemy enemy = _enemies[i];
        _moveEnemy(enemy, dt, screenSize);
        
        if (enemy.progress >= 1.0) {
          _lives--;
          _enemies.removeAt(i);
          if (_lives <= 0) {
            _gameOver = true;
          }
        } else if (enemy.hp <= 0) {
          _money += 15; // Reward
          _enemies.removeAt(i);
        }
      }

      // Check for next wave
      if (_enemies.isEmpty && _waveTimer?.isActive == false && !_gameOver) {
         // Simple auto-wave for this demo
         if (Random().nextInt(100) == 0) { // Small delay chance
           _wave++;
           _startWave();
         }
      }

      // 2. Towers Attack
      for (Tower tower in _towers) {
        tower.timeSinceLastShot += dt;
        if (tower.timeSinceLastShot >= tower.cooldown) {
          Enemy? target = _findTarget(tower);
          if (target != null) {
            tower.timeSinceLastShot = 0;
            _projectiles.add(Projectile(
              id: DateTime.now().toString(),
              x: tower.x,
              y: tower.y,
              targetX: target.x,
              targetY: target.y,
              damage: tower.damage,
              targetEnemyId: target.id,
              type: tower.type,
            ));
          }
        }
      }

      // 3. Update Projectiles
      for (int i = _projectiles.length - 1; i >= 0; i--) {
        Projectile p = _projectiles[i];
        _moveProjectile(p, dt);
        
        // Simple collision logic (distance check)
        bool hit = false;
        // Update target position if enemy still exists
        try {
          Enemy target = _enemies.firstWhere((e) => e.id == p.targetEnemyId);
          double dx = target.x - p.x;
          double dy = target.y - p.y;
          double dist = sqrt(dx*dx + dy*dy);
          
          if (dist < 20) { // Hit radius
            target.hp -= p.damage;
            hit = true;
          } else {
            // Homing missile logic
            double angle = atan2(dy, dx);
            p.targetX = target.x;
            p.targetY = target.y;
          }
        } catch (e) {
          // Target dead, just continue to last known pos or remove
          hit = true; // Remove if target lost
        }

        if (hit) {
          _projectiles.removeAt(i);
        }
      }
    });
  }

  void _moveEnemy(Enemy enemy, double dt, Size screenSize) {
    // Calculate total path length in pixels to normalize speed
    // For simplicity, we treat path segments as equal length or just use progress
    // A better way is to calculate real pixels.
    
    // Let's map progress (0.0-1.0) to path segments
    int segmentCount = _pathPoints.length - 1;
    double totalProgress = enemy.progress * segmentCount;
    int currentSegment = totalProgress.floor();
    double segmentProgress = totalProgress - currentSegment;
    
    if (currentSegment >= segmentCount) {
      enemy.progress = 1.0;
      return;
    }

    Offset p1 = _scalePoint(_pathPoints[currentSegment], screenSize);
    Offset p2 = _scalePoint(_pathPoints[currentSegment + 1], screenSize);
    
    // Move logic
    // Speed is roughly % of screen per second
    double moveSpeed = enemy.speed * 0.5; // Adjust factor
    enemy.progress += moveSpeed * dt;
    
    // Update X,Y for rendering and collision
    // Re-calculate based on new progress
    totalProgress = enemy.progress * segmentCount;
    currentSegment = totalProgress.floor();
    segmentProgress = totalProgress - currentSegment;
    
    if (currentSegment < segmentCount) {
      p1 = _scalePoint(_pathPoints[currentSegment], screenSize);
      p2 = _scalePoint(_pathPoints[currentSegment + 1], screenSize);
      enemy.x = p1.dx + (p2.dx - p1.dx) * segmentProgress;
      enemy.y = p1.dy + (p2.dy - p1.dy) * segmentProgress;
    }
  }

  void _moveProjectile(Projectile p, double dt) {
    double dx = p.targetX - p.x;
    double dy = p.targetY - p.y;
    double angle = atan2(dy, dx);
    
    p.x += cos(angle) * p.speed * dt;
    p.y += sin(angle) * p.speed * dt;
  }

  Enemy? _findTarget(Tower tower) {
    Enemy? bestTarget;
    double minDist = tower.range; // Start with max range

    for (Enemy enemy in _enemies) {
      double dx = enemy.x - tower.x;
      double dy = enemy.y - tower.y;
      double dist = sqrt(dx*dx + dy*dy);
      
      if (dist <= tower.range) {
        // Simple logic: target closest to end (highest progress)
        if (bestTarget == null || enemy.progress > bestTarget.progress) {
          bestTarget = enemy;
        }
      }
    }
    return bestTarget;
  }

  Offset _scalePoint(Offset p, Size size) {
    return Offset(p.dx * size.width, p.dy * size.height);
  }

  void _placeTower(TapDownDetails details) {
    if (_gameOver) return;
    if (_selectedTowerType == null) return;
    
    int cost = Tower.getCost(_selectedTowerType!);
    if (_money < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('金币不足! (Not enough money)')),
      );
      return;
    }

    // Check if placing on path (Simple check: distance to any path segment)
    // For MVP, we just allow placement anywhere not too close to path
    // Skipping complex path collision for now to keep code simple
    
    setState(() {
      _money -= cost;
      _towers.add(Tower(
        id: DateTime.now().toString(),
        x: details.localPosition.dx,
        y: details.localPosition.dy,
        type: _selectedTowerType!,
      ));
      _selectedTowerType = null; // Deselect after placement
    });
  }

  @override
  Widget build(BuildContext context) {
    Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Map Background
          Container(color: Colors.green[50]),
          
          // 2. Path
          CustomPaint(
            size: Size.infinite,
            painter: PathPainter(_pathPoints),
          ),

          // 3. Towers
          ..._towers.map((t) => Positioned(
            left: t.x - 20,
            top: t.y - 20,
            child: _buildTowerWidget(t),
          )),

          // 4. Enemies
          ..._enemies.map((e) => Positioned(
            left: e.x - 15,
            top: e.y - 15,
            child: _buildEnemyWidget(e),
          )),

          // 5. Projectiles
          ..._projectiles.map((p) => Positioned(
            left: p.x - 5,
            top: p.y - 5,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _getProjectileColor(p.type),
                shape: BoxShape.circle,
              ),
            ),
          )),

          // 6. Interaction Layer (Tap to place)
          GestureDetector(
            onTapDown: _placeTower,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),

          // 7. HUD / UI
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.black54,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Wave: $_wave', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('Lives: $_lives', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      Text('Money: \$$_money', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (_gameOver)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      color: Colors.black87,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("GAME OVER", style: TextStyle(color: Colors.red, fontSize: 30)),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _gameOver = false;
                                _money = GameConfig.startingMoney;
                                _lives = GameConfig.startingLives;
                                _wave = 1;
                                _enemies.clear();
                                _towers.clear();
                                _projectiles.clear();
                                _startWave();
                              });
                            },
                            child: const Text("Restart"),
                          )
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                // Bottom Bar (Tower Selection)
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: PokemonType.values.map((type) {
                      bool isSelected = _selectedTowerType == type;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedTowerType = type),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue[100] : Colors.grey[100],
                            border: isSelected ? Border.all(color: Colors.blue, width: 2) : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              _getPokemonIcon(type),
                              Text(Tower.getName(type)),
                              Text("\$${Tower.getCost(type)}", style: const TextStyle(fontSize: 12, color: Colors.green)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTowerWidget(Tower t) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 1),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Center(child: _getPokemonIcon(t.type)),
        ),
        // Range indicator (optional, maybe only when selected)
      ],
    );
  }

  Widget _buildEnemyWidget(Enemy e) {
    return Column(
      children: [
        // HP Bar
        Container(
          width: 30,
          height: 4,
          color: Colors.red[100],
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (e.hp / e.maxHp).clamp(0.0, 1.0),
            child: Container(color: Colors.red),
          ),
        ),
        const SizedBox(height: 2),
        const Icon(Icons.bug_report, color: Colors.purple, size: 30),
      ],
    );
  }

  Widget _getPokemonIcon(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu:
        return const Icon(Icons.flash_on, color: Colors.yellow, size: 24);
      case PokemonType.charmander:
        return const Icon(Icons.local_fire_department, color: Colors.orange, size: 24);
      case PokemonType.bulbasaur:
        return const Icon(Icons.grass, color: Colors.green, size: 24);
    }
  }

  Color _getProjectileColor(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return Colors.yellow;
      case PokemonType.charmander: return Colors.orange;
      case PokemonType.bulbasaur: return Colors.green;
    }
  }
}

class PathPainter extends CustomPainter {
  final List<Offset> normalizedPoints;

  PathPainter(this.normalizedPoints);

  @override
  void paint(Canvas canvas, Size size) {
    if (normalizedPoints.isEmpty) return;

    Paint paint = Paint()
      ..color = Colors.brown.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 40
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path path = Path();
    Offset start = _scale(normalizedPoints[0], size);
    path.moveTo(start.dx, start.dy);

    for (int i = 1; i < normalizedPoints.length; i++) {
      Offset p = _scale(normalizedPoints[i], size);
      path.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(path, paint);
    
    // Draw start and end points
    Paint pointPaint = Paint()..style = PaintingStyle.fill;
    
    // Start (Green)
    canvas.drawCircle(start, 10, pointPaint..color = Colors.green);
    
    // End (Red)
    canvas.drawCircle(_scale(normalizedPoints.last, size), 10, pointPaint..color = Colors.red);
  }

  Offset _scale(Offset p, Size size) {
    return Offset(p.dx * size.width, p.dy * size.height);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
