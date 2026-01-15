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
  bool _paused = false; // New: Pause feature
  
  // Entities
  List<Enemy> _enemies = [];
  List<Tower> _towers = [];
  List<Projectile> _projectiles = [];
  List<GoldDrop> _goldDrops = []; // New: Gold drop animations
  
  // Wave Management
  Timer? _waveTimer;
  int _enemiesSpawnedInWave = 0;
  
  // UI State
  PokemonType? _selectedTowerType;
  Tower? _selectedTower; // New: For upgrading
  
  // Path Definition (More complex for variety)
  final List<Offset> _pathPoints = [
    const Offset(0.0, 0.3),
    const Offset(0.3, 0.3),
    const Offset(0.3, 0.6),
    const Offset(0.7, 0.6),
    const Offset(0.7, 0.2),
    const Offset(1.0, 0.2),
  ];
  
  // Animations
  late AnimationController _waveTextController;
  late Animation<double> _waveTextAnimation;
  
  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_gameLoop);
    _ticker.start();
    _startWave();
    
    // Animation for wave start text
    _waveTextController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _waveTextAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_waveTextController);
  }
  
  @override
  void dispose() {
    _ticker.dispose();
    _waveTimer?.cancel();
    _waveTextController.dispose();
    super.dispose();
  }
  
  void _startWave() {
    if (_paused) return;
    _enemiesSpawnedInWave = 0;
    _waveTextController.forward(from: 0.0); // Animate wave start
    _waveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_gameOver || _paused) {
        timer.cancel();
        return;
      }
      
      if (_enemiesSpawnedInWave < _wave * 5) {
        _spawnEnemy();
        _enemiesSpawnedInWave++;
      } else {
        timer.cancel();
        // Auto-start next wave after delay
        Future.delayed(const Duration(seconds: 3), () {
          if (!_gameOver && !_paused) {
            _wave++;
            _startWave();
          }
        });
      }
    });
  }
  
  void _spawnEnemy() {
    setState(() {
      // Random enemy types for variety
      PokemonType enemyType = PokemonType.values[Random().nextInt(PokemonType.values.length)];
      double hp = 100.0 + (_wave * 20);
      double speed = 0.1 + (_wave * 0.01) + Random().nextDouble() * 0.05; // Slight randomization
      _enemies.add(Enemy(
        id: DateTime.now().toString() + Random().nextInt(1000).toString(),
        maxHp: hp,
        hp: hp,
        speed: speed,
        type: enemyType,
      ));
    });
  }
  
  void _gameLoop(Duration elapsed) {
    if (_gameOver || _paused) return;
    
    double currentTime = elapsed.inMilliseconds / 1000.0;
    double dt = currentTime - _lastTime;
    _lastTime = currentTime;
    
    if (dt > 0.1) dt = 0.1; // Cap delta time
    
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
          // Gold drop animation
          _goldDrops.add(GoldDrop(
            x: enemy.x,
            y: enemy.y,
            amount: 15 + Random().nextInt(10),
          ));
          _money += 15;
          _enemies.removeAt(i);
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
        
        bool hit = false;
        try {
          Enemy target = _enemies.firstWhere((e) => e.id == p.targetEnemyId);
          double dx = target.x - p.x;
          double dy = target.y - p.y;
          double dist = sqrt(dx*dx + dy*dy);
          
          if (dist < 20) {
            target.hp -= p.damage;
            hit = true;
          } else {
            double angle = atan2(dy, dx);
            p.targetX = target.x;
            p.targetY = target.y;
          }
        } catch (e) {
          hit = true;
        }
        
        if (hit) {
          _projectiles.removeAt(i);
        }
      }
      
      // 4. Update Gold Drops
      for (int i = _goldDrops.length - 1; i >= 0; i--) {
        GoldDrop drop = _goldDrops[i];
        drop.y += 100 * dt; // Float up
        drop.opacity -= 0.5 * dt;
        if (drop.opacity <= 0) {
          _goldDrops.removeAt(i);
        }
      }
    });
  }
  
  void _moveEnemy(Enemy enemy, double dt, Size screenSize) {
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
    
    double moveSpeed = enemy.speed * 0.5;
    enemy.progress += moveSpeed * dt;
    
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
    double minDist = tower.range;
    
    for (Enemy enemy in _enemies) {
      double dx = enemy.x - tower.x;
      double dy = enemy.y - tower.y;
      double dist = sqrt(dx*dx + dy*dy);
      
      if (dist <= tower.range) {
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
    if (_gameOver || _paused) return;
    if (_selectedTowerType == null) return;
    
    int cost = Tower.getCost(_selectedTowerType!);
    if (_money < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('金币不足! (Not enough money)'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    
    // Simple path collision (avoid placing too close to path)
    bool onPath = false;
    for (Offset point in _pathPoints) {
      Offset scaled = _scalePoint(point, MediaQuery.of(context).size);
      if ((scaled - details.localPosition).distance < 50) {
        onPath = true;
        break;
      }
    }
    if (onPath) return;
    
    setState(() {
      _money -= cost;
      _towers.add(Tower(
        id: DateTime.now().toString(),
        x: details.localPosition.dx,
        y: details.localPosition.dy,
        type: _selectedTowerType!,
      ));
      _selectedTowerType = null;
    });
  }
  
  void _upgradeTower(Tower tower) {
    int cost = 25; // Upgrade cost
    if (_money >= cost) {
      setState(() {
        _money -= cost;
        tower.damage += 10;
        tower.range += 20;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    Size screenSize = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Stack(
        children: [
          // 1. Background (Gradient for Q-moe style)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.lightGreenAccent, Colors.lightBlueAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          // 2. Path
          CustomPaint(
            size: Size.infinite,
            painter: PathPainter(_pathPoints),
          ),
          
          // 3. Towers
          ..._towers.map((t) => Positioned(
            left: t.x - 25,
            top: t.y - 25,
            child: GestureDetector(
              onTap: () => setState(() => _selectedTower = t),
              child: _buildTowerWidget(t),
            ),
          )),
          
          // 4. Tower Range Preview
          if (_selectedTowerType != null)
            Positioned.fill(
              child: CustomPaint(
                painter: RangePainter(
                  center: Offset.zero, // Will be set in painter
                  range: Tower._getRange(_selectedTowerType!),
                  screenSize: screenSize,
                ),
              ),
            ),
          
          // 5. Enemies
          ..._enemies.map((e) => Positioned(
            left: e.x - 20,
            top: e.y - 20,
            child: _buildEnemyWidget(e),
          )),
          
          // 6. Projectiles
          ..._projectiles.map((p) => Positioned(
            left: p.x - 8,
            top: p.y - 8,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _getProjectileColor(p.type),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _getProjectileColor(p.type).withOpacity(0.5), blurRadius: 10)],
              ),
            ),
          )),
          
          // 7. Gold Drops
          ..._goldDrops.map((g) => Positioned(
            left: g.x - 10,
            top: g.y - 10,
            child: Opacity(
              opacity: g.opacity,
              child: Text(
                '+${g.amount}',
                style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          )),
          
          // 8. Tap Layer
          GestureDetector(
            onTapDown: _placeTower,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
          
          // 9. HUD
          SafeArea(
            child: Column(
              children: [
                // Top Bar (Improved with cards and icons)
                Card(
                  color: Colors.white.withOpacity(0.9),
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.access_time, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text('Wave: $_wave', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.favorite, color: Colors.red),
                            const SizedBox(width: 4),
                            Text('Lives: $_lives', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.attach_money, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text('Money: $_money', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        IconButton(
                          icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                          onPressed: () => setState(() => _paused = !_paused),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Wave Start Animation
                if (_waveTextAnimation.value > 0)
                  FadeTransition(
                    opacity: _waveTextAnimation,
                    child: Center(
                      child: Card(
                        color: Colors.yellowAccent.withOpacity(0.8),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Wave $_wave Starting!', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                
                if (_gameOver)
                  Center(
                    child: Card(
                      color: Colors.black.withOpacity(0.9),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("GAME OVER", style: TextStyle(color: Colors.red, fontSize: 30, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                              onPressed: () {
                                setState(() {
                                  _gameOver = false;
                                  _paused = false;
                                  _money = GameConfig.startingMoney;
                                  _lives = GameConfig.startingLives;
                                  _wave = 1;
                                  _enemies.clear();
                                  _towers.clear();
                                  _projectiles.clear();
                                  _goldDrops.clear();
                                  _startWave();
                                });
                              },
                              child: const Text("Restart", style: TextStyle(color: Colors.white)),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                // Bottom Bar (Tower Selection)
                Card(
                  color: Colors.white.withOpacity(0.9),
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: PokemonType.values.map((type) {
                        bool isSelected = _selectedTowerType == type;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedTowerType = type),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.blue[100] : Colors.grey[100],
                              border: isSelected ? Border.all(color: Colors.blue, width: 3) : null,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: isSelected ? [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 8)] : null,
                            ),
                            child: Column(
                              children: [
                                _getPokemonIcon(type),
                                Text(Tower.getName(type), style: const TextStyle(fontSize: 12)),
                                Text("\$${Tower.getCost(type)}", style: const TextStyle(fontSize: 10, color: Colors.green)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                // Upgrade Panel
                if (_selectedTower != null)
                  Card(
                    color: Colors.white.withOpacity(0.9),
                    margin: const EdgeInsets.all(8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              _upgradeTower(_selectedTower!);
                              _selectedTower = null;
                            },
                            child: const Text('Upgrade (\$25)'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _selectedTower = null),
                          ),
                        ],
                      ),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(0, 2))],
        gradient: LinearGradient(colors: [Colors.white, Colors.grey[200]!]),
      ),
      child: Center(child: _getPokemonIcon(t.type)),
    );
  }
  
  Widget _buildEnemyWidget(Enemy e) {
    return Column(
      children: [
        // HP Bar (Improved)
        Container(
          width: 35,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.red[100],
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (e.hp / e.maxHp).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.red, Colors.redAccent]),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        // Enemy Body (More cute)
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _getEnemyColor(e.type),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Center(child: Icon(_getEnemyIcon(e.type), color: Colors.white, size: 20)),
        ),
      ],
    );
  }
  
  Widget _getPokemonIcon(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu:
        return const Icon(Icons.flash_on, color: Colors.yellow, size: 28);
      case PokemonType.charmander:
        return const Icon(Icons.local_fire_department, color: Colors.orange, size: 28);
      case PokemonType.bulbasaur:
        return const Icon(Icons.grass, color: Colors.green, size: 28);
    }
  }
  
  Color _getProjectileColor(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return Colors.yellow;
      case PokemonType.charmander: return Colors.orange;
      case PokemonType.bulbasaur: return Colors.green;
    }
  }
  
  IconData _getEnemyIcon(PokemonType type) {
    switch (type) {
      case PokemonType.pikachu: return Icons.flash_on;
      case PokemonType.charmander: return Icons.local_fire_department;
      case PokemonType.bulbasaur: return Icons.grass;
    }
  }
  
  Color _getEnemyColor(PokemonType type) {
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
      ..shader = LinearGradient(colors: [Colors.brown, Colors.brown[300]!]).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 50
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
    
    // Start and end points (More cute)
    Paint pointPaint = Paint()..style = PaintingStyle.fill;
    canvas.drawCircle(start, 15, pointPaint..color = Colors.greenAccent);
    canvas.drawCircle(_scale(normalizedPoints.last, size), 15, pointPaint..color = Colors.redAccent);
  }
  
  Offset _scale(Offset p, Size size) {
    return Offset(p.dx * size.width, p.dy * size.height);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RangePainter extends CustomPainter {
  final Offset center;
  final double range;
  final Size screenSize;
  
  RangePainter({required this.center, required this.range, required this.screenSize});
  
  @override
  void paint(Canvas canvas, Size size) {
    // Note: This is a placeholder; actual implementation would need tap position
    Paint paint = Paint()
      ..color = Colors.blue.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), range, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
