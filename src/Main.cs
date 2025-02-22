using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

// Compiler Notes:
// Doesn't support arrow expression-bodied property syntax for explicit get accessors
// Doesn't support inline collection initializers (and tuple initializers)
// No support for string interpolation ($"" syntax)

public struct Move {
    public int dx;
    public int dy;
    public Move(int dx, int dy) {
        this.dx = dx;
        this.dy = dy;
    }
}

public class GameForm : Form {
    Timer logicTimer;
    Timer renderTimer;
    List<Point> playerSnake;
    List<Point> enemySnake;
    // Store the previous positions for interpolation.
    List<PointF> prevPlayerSnake;
    List<PointF> prevEnemySnake;
    
    // Updated: store previous food positions by their ID.
    Dictionary<int, Point> prevFoodPositions = new Dictionary<int, Point>();
    List<Food> foods = new List<Food>();
    int cellSize = 10, cols = 40, rows = 40;
    int playerDX = 1, playerDY = 0;
    int enemyDX = 1, enemyDY = 0;
    int playerScore = 0, enemyScore = 0;
    Random rand = new Random();
    float animationPhase = 0f;
    Color playerBaseColor = Color.Green;
    bool gameStarted = false;
    bool keyboardOverride = false;
    int pendingDX, pendingDY;
    Point currentMousePosition;

    // Visual effect variables
    private float glowIntensity = 1.0f;
    private float rainbowPhase = 0f;
    private const float RAINBOW_SPEED = 0.05f;

    // Time tracking for interpolation
    DateTime lastUpdateTime;

    // New fields for magnet effect (counts down ticks)
    int playerMagnetTicks = 0, enemyMagnetTicks = 0;

    // Food struct updated with an ID.
    private struct Food {
        public int Id;
        public Point Position;
        public bool IsSpecial;
        public bool IsMagnetic;  // NEW: magnetic food flag
        public Color FoodColor;
    }
    
    // Counter for assigning unique IDs to foods.
    int nextFoodId = 0;

    public GameForm() {
        this.ClientSize = new Size(cols * cellSize, rows * cellSize + 40);
        this.DoubleBuffered = true;
        this.Text = "Snek - Mouse or Arrow/WASD (keys override mouse)";
        this.KeyPreview = true;

        playerSnake = new List<Point> { new Point(cols / 2, rows / 2) };
        enemySnake = new List<Point> { new Point(cols / 4, rows / 4) };
        // Initialize previous positions as the same as starting positions.
        prevPlayerSnake = playerSnake.Select(p => new PointF(p.X, p.Y)).ToList();
        prevEnemySnake = enemySnake.Select(p => new PointF(p.X, p.Y)).ToList();
        GenerateFoods();

        pendingDX = playerDX;
        pendingDY = playerDY;

        // Logic timer (game ticks every 100ms)
        logicTimer = new Timer { Interval = 100 };
        logicTimer.Tick += (s, e) => UpdateGame();

        // Render timer for smooth animation (~60 FPS)
        renderTimer = new Timer { Interval = 16 };
        renderTimer.Tick += (s, e) => Invalidate();

        this.MouseClick += (s, e) => {
            if (!gameStarted && e.Button == MouseButtons.Left) {
                gameStarted = true;
                lastUpdateTime = DateTime.Now;
                logicTimer.Start();
                renderTimer.Start();
            }
        };

        this.MouseMove += (s, e) => {
            if (!keyboardOverride)
                currentMousePosition = e.Location;
        };

        this.KeyDown += GameForm_KeyDown;
    }

    // Helper for linear interpolation (for PointF)
    private PointF Lerp(PointF a, PointF b, float t) {
        return new PointF(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t);
    }

    // Method to create a glow effect path
    private GraphicsPath CreateGlowPath(PointF center, float radius, float glowSize) {
        GraphicsPath path = new GraphicsPath();
        for (float size = radius; size <= radius + glowSize; size += glowSize / 4) {
            path.AddEllipse(center.X - size, center.Y - size, size * 2, size * 2);
        }
        return path;
    }

    // Generates a rainbow color based on the phase value
    private Color GetRainbowColor(float phase) {
        float frequency = 2.0f * (float)Math.PI;
        int r = (int)(Math.Sin(frequency * phase + 0) * 127 + 128);
        int g = (int)(Math.Sin(frequency * phase + 2) * 127 + 128);
        int b = (int)(Math.Sin(frequency * phase + 4) * 127 + 128);
        return Color.FromArgb(r, g, b);
    }

    // Draws a shiny eye with an inner gradient
    private void DrawShinyEye(Graphics g, PointF center, float eyeRadius, float pupilRadius) {
        RectangleF eyeRect = new RectangleF(
            center.X - eyeRadius, 
            center.Y - eyeRadius,
            eyeRadius * 2,
            eyeRadius * 2
        );
        
        // White of the eye
        g.FillEllipse(Brushes.White, eyeRect);
        
        // Shine effect
        using (PathGradientBrush shine = new PathGradientBrush(new PointF[] {
            new PointF(center.X - eyeRadius * 0.7f, center.Y - eyeRadius * 0.7f),
            new PointF(center.X + eyeRadius * 0.7f, center.Y - eyeRadius * 0.7f),
            new PointF(center.X, center.Y + eyeRadius * 0.7f)
        })) {
            shine.CenterColor = Color.FromArgb(150, 255, 255, 255);
            shine.SurroundColors = new Color[] { Color.FromArgb(0, 255, 255, 255) };
            g.FillEllipse(shine, eyeRect);
        }

        // Pupil with gradient
        RectangleF pupilRect = new RectangleF(
            center.X - pupilRadius,
            center.Y - pupilRadius,
            pupilRadius * 2,
            pupilRadius * 2
        );
        
        using (PathGradientBrush pupilBrush = new PathGradientBrush(new PointF[] {
            new PointF(center.X - pupilRadius, center.Y - pupilRadius),
            new PointF(center.X + pupilRadius, center.Y - pupilRadius),
            new PointF(center.X + pupilRadius, center.Y + pupilRadius),
            new PointF(center.X - pupilRadius, center.Y + pupilRadius)
        })) {
            pupilBrush.CenterColor = Color.Black;
            pupilBrush.SurroundColors = new Color[] { Color.FromArgb(255, 40, 40, 40) };
            g.FillEllipse(pupilBrush, pupilRect);
        }
    }

    private void GameForm_KeyDown(object sender, KeyEventArgs e) {
        keyboardOverride = true;
        int newDX = pendingDX, newDY = pendingDY;
        switch (e.KeyCode) {
            case Keys.Up:
            case Keys.W:
                newDX = 0; newDY = -1;
                break;
            case Keys.Down:
            case Keys.S:
                newDX = 0; newDY = 1;
                break;
            case Keys.Left:
            case Keys.A:
                newDX = -1; newDY = 0;
                break;
            case Keys.Right:
            case Keys.D:
                newDX = 1; newDY = 0;
                break;
        }
        if (playerSnake.Count > 1) {
            int currentDX = playerSnake[0].X - playerSnake[1].X;
            int currentDY = playerSnake[0].Y - playerSnake[1].Y;
            if (newDX == -currentDX && newDY == -currentDY)
                return;
        }
        pendingDX = newDX;
        pendingDY = newDY;
    }

    void UpdateGame() {
        // Save current snake positions for interpolation.
        prevPlayerSnake = playerSnake.Select(p => new PointF(p.X, p.Y)).ToList();
        prevEnemySnake = enemySnake.Select(p => new PointF(p.X, p.Y)).ToList();

        // Save current food positions for interpolation.
        var newPrevFoodPositions = new Dictionary<int, Point>();
        foreach (var food in foods)
            newPrevFoodPositions[food.Id] = food.Position;
        prevFoodPositions = newPrevFoodPositions;

        animationPhase += 0.2f;
        if (animationPhase > Math.PI * 2)
            animationPhase -= (float)(Math.PI * 2);

        // Update rainbow and glow effects
        rainbowPhase += RAINBOW_SPEED;
        if (rainbowPhase > 1.0f) rainbowPhase -= 1.0f;
        
        glowIntensity = 0.7f + (float)Math.Sin(animationPhase) * 0.3f;

        // --- Player Update ---
        int candidateDX, candidateDY;
        if (!keyboardOverride) {
            int mouseCellX = currentMousePosition.X / cellSize;
            int mouseCellY = currentMousePosition.Y / cellSize;
            int diffX = mouseCellX - playerSnake[0].X;
            int diffY = mouseCellY - playerSnake[0].Y;
            if (Math.Abs(diffX) > Math.Abs(diffY)) {
                candidateDX = diffX > 0 ? 1 : (diffX < 0 ? -1 : playerDX);
                candidateDY = 0;
            } else if(diffY != 0) {
                candidateDY = diffY > 0 ? 1 : -1;
                candidateDX = 0;
            } else {
                candidateDX = playerDX;
                candidateDY = playerDY;
            }
        } else {
            candidateDX = pendingDX;
            candidateDY = pendingDY;
        }

        if (playerSnake.Count > 1) {
            int currentDX = playerSnake[0].X - playerSnake[1].X;
            int currentDY = playerSnake[0].Y - playerSnake[1].Y;
            if (candidateDX == -currentDX && candidateDY == -currentDY) {
                candidateDX = playerDX;
                candidateDY = playerDY;
            }
        }
        playerDX = candidateDX;
        playerDY = candidateDY;

        Point playerHead = playerSnake[0];
        Point newPlayerHead = new Point(playerHead.X + playerDX, playerHead.Y + playerDY);
        if (IsOutOfBounds(newPlayerHead) || playerSnake.Skip(1).Contains(newPlayerHead) || enemySnake.Skip(1).Contains(newPlayerHead)) {
            logicTimer.Stop();
            renderTimer.Stop();
            MessageBox.Show("Game Over! Your Score: " + playerScore);
            Application.Exit();
            return;
        }
        playerSnake.Insert(0, newPlayerHead);
        int foodIndex = foods.FindIndex(f => Math.Max(Math.Abs(newPlayerHead.X - f.Position.X), Math.Abs(newPlayerHead.Y - f.Position.Y)) <= 1);
        if (foodIndex != -1) {
            Food eaten = foods[foodIndex];
            if (eaten.IsMagnetic) {
                // Magnetic food: add 3 segments and start magnet effect (100 ticks)
                playerScore += 20;
                Point tail = playerSnake[playerSnake.Count - 1];
                for (int i = 0; i < 3; i++) {
                    playerSnake.Add(tail);
                }
                playerMagnetTicks = 100;
            }
            else if (eaten.IsSpecial) {
                playerScore += 100;
                // Add extra segments to the player's snake
                Point tail = playerSnake[playerSnake.Count - 1];
                for (int i = 0; i < 30; i++) {
                    playerSnake.Add(tail);
                }
            } else {
                playerScore += 10;
            }
            foods.RemoveAt(foodIndex);
            if (foods.Count == 0)
                GenerateFoods();
        } else {
            playerSnake.RemoveAt(playerSnake.Count - 1);
        }

        // --- Enemy Update ---
        if (foods.Count == 0)
            GenerateFoods();
        Point enemyHead = enemySnake[0];
        Food targetFood = foods.OrderBy(f => Math.Abs(f.Position.X - enemyHead.X) + Math.Abs(f.Position.Y - enemyHead.Y)).First();

        int enemyDiffX = targetFood.Position.X - enemyHead.X;
        int enemyDiffY = targetFood.Position.Y - enemyHead.Y;
        int candidateEnemyDX = Math.Abs(enemyDiffX) > Math.Abs(enemyDiffY) ? (enemyDiffX > 0 ? 1 : -1) : 0;
        int candidateEnemyDY = candidateEnemyDX == 0 ? (enemyDiffY > 0 ? 1 : -1) : 0;

        if (enemySnake.Count > 1) {
            int currentEnemyDX = enemyHead.X - enemySnake[1].X;
            int currentEnemyDY = enemyHead.Y - enemySnake[1].Y;
            if (candidateEnemyDX == -currentEnemyDX && candidateEnemyDY == -currentEnemyDY) {
                candidateEnemyDX = currentEnemyDX;
                candidateEnemyDY = currentEnemyDY;
            }
        }

        Point candidateEnemyHead = new Point(enemyHead.X + candidateEnemyDX, enemyHead.Y + candidateEnemyDY);
        bool candidateGrowing = candidateEnemyHead.Equals(targetFood.Position);
        var enemyBodyToCheck = (!candidateGrowing && enemySnake.Count > 1) ? enemySnake.Skip(1).Take(enemySnake.Count - 1) : enemySnake.Skip(1);
        bool safe = !IsOutOfBounds(candidateEnemyHead) && !enemyBodyToCheck.Contains(candidateEnemyHead);

        if (!safe) {
            var moves = new List<Move> { new Move(1, 0), new Move(-1, 0), new Move(0, 1), new Move(0, -1) };
            if (enemySnake.Count > 1) {
                int currentEnemyDX = enemyHead.X - enemySnake[1].X;
                int currentEnemyDY = enemyHead.Y - enemySnake[1].Y;
                moves.RemoveAll(m => m.dx == -currentEnemyDX && m.dy == -currentEnemyDY);
            }
            foreach (var move in moves.OrderBy(m => Math.Abs((enemyHead.X + m.dx) - targetFood.Position.X) + Math.Abs((enemyHead.Y + m.dy) - targetFood.Position.Y))) {
                Point newHead = new Point(enemyHead.X + move.dx, enemyHead.Y + move.dy);
                bool growing = newHead.Equals(targetFood.Position);
                var checkBody = (!growing && enemySnake.Count > 1) ? enemySnake.Skip(1).Take(enemySnake.Count - 1) : enemySnake.Skip(1);
                if (!IsOutOfBounds(newHead) && !checkBody.Contains(newHead)) {
                    candidateEnemyDX = move.dx;
                    candidateEnemyDY = move.dy;
                    safe = true;
                    break;
                }
            }
        }
        enemyDX = candidateEnemyDX;
        enemyDY = candidateEnemyDY;

        Point newEnemyHead = new Point(enemyHead.X + enemyDX, enemyHead.Y + enemyDY);
        if (IsOutOfBounds(newEnemyHead) || enemySnake.Skip(1).Contains(newEnemyHead) || playerSnake.Skip(1).Contains(newEnemyHead)) {
            RespawnEnemy();
        } else {
            enemySnake.Insert(0, newEnemyHead);
            int enemyFoodIndex = foods.FindIndex(f => Math.Max(Math.Abs(newEnemyHead.X - f.Position.X), Math.Abs(newEnemyHead.Y - f.Position.Y)) <= 1);
            if (enemyFoodIndex != -1) {
                Food eaten = foods[enemyFoodIndex];
                if (eaten.IsMagnetic) {
                    enemyScore += 20;
                    Point tail = enemySnake[enemySnake.Count - 1];
                    for (int i = 0; i < 3; i++) {
                        enemySnake.Add(tail);
                    }
                    enemyMagnetTicks = 100;
                }
                else if (eaten.IsSpecial) {
                    enemyScore += 100;
                    Point tail = enemySnake[enemySnake.Count - 1];
                    for (int i = 0; i < 10; i++) {
                        enemySnake.Add(tail);
                    }
                } else {
                    enemyScore += 10;
                }
                foods.RemoveAt(enemyFoodIndex);
                if (foods.Count == 0)
                    GenerateFoods();
            } else {
                enemySnake.RemoveAt(enemySnake.Count - 1);
            }
        }

        // --- Magnetic Food Attraction ---
        // If either snake has an active magnet effect, move each food 1 unit toward that snake’s head.
        if (playerMagnetTicks > 0 || enemyMagnetTicks > 0) {
            for (int i = 0; i < foods.Count; i++) {
                bool playerActive = playerMagnetTicks > 0;
                bool enemyActive = enemyMagnetTicks > 0;
                Point target;
                if (playerActive && enemyActive) {
                    int distPlayer = Math.Abs(foods[i].Position.X - playerSnake[0].X) + Math.Abs(foods[i].Position.Y - playerSnake[0].Y);
                    int distEnemy = Math.Abs(foods[i].Position.X - enemySnake[0].X) + Math.Abs(foods[i].Position.Y - enemySnake[0].Y);
                    target = (distPlayer <= distEnemy) ? playerSnake[0] : enemySnake[0];
                } else if (playerActive) {
                    target = playerSnake[0];
                } else { // enemyActive
                    target = enemySnake[0];
                }
                int dx = target.X - foods[i].Position.X;
                int dy = target.Y - foods[i].Position.Y;
                int moveX = dx == 0 ? 0 : (dx > 0 ? 1 : -1);
                int moveY = dy == 0 ? 0 : (dy > 0 ? 1 : -1);
                Food f = foods[i];
                f.Position = new Point(f.Position.X + moveX, f.Position.Y + moveY);
                foods[i] = f;
            }
        }

        // Decrement magnet timers
        if (playerMagnetTicks > 0) playerMagnetTicks--;
        if (enemyMagnetTicks > 0) enemyMagnetTicks--;

        // Mark the time after the logic update.
        lastUpdateTime = DateTime.Now;
    }

    bool IsOutOfBounds(Point p) {
        return p.X < 0 || p.Y < 0 || p.X >= cols || p.Y >= rows;
    }

    void GenerateFoods() {
        // When generating new foods, assign each a unique ID.
        double chance = rand.NextDouble();
        int count = chance < 0.25 ? 3 : (chance < 0.75 ? 2 : 1);
        for (int i = 0; i < count; i++) {
            Food newFood;
            do {
                newFood.Position = new Point(rand.Next(0, cols), rand.Next(0, rows));
            } while (playerSnake.Contains(newFood.Position) ||
                     enemySnake.Contains(newFood.Position) ||
                     foods.Any(f => f.Position == newFood.Position));
            // Determine food type:
            double magneticChance = 0.065;
            double specialChance = 0.075;
            if (rand.NextDouble() < magneticChance) {
                newFood.IsMagnetic = true;
                newFood.IsSpecial = false;
                newFood.FoodColor = Color.Red; // initial color (will oscillate)
            }
            else if (rand.NextDouble() < specialChance) {
                newFood.IsSpecial = true;
                newFood.IsMagnetic = false;
                newFood.FoodColor = Color.Empty;
            } else {
                newFood.IsSpecial = false;
                newFood.IsMagnetic = false;
                newFood.FoodColor = Color.Red;
            }
            newFood.Id = nextFoodId++;
            foods.Add(newFood);
        }
    }

    void RespawnEnemy() {
        enemySnake.Clear();
        Point p;
        do {
            p = new Point(rand.Next(0, cols), rand.Next(0, rows));
        } while (playerSnake.Contains(p) || foods.Any(f => f.Position == p));
        enemySnake.Add(p);
        enemyScore /= 2;
        enemyDX = 1;
        enemyDY = 0;
    }

    Color InterpolateColor(Color start, Color end, float t) {
        int r = (int)(start.R + (end.R - start.R) * t);
        int g = (int)(start.G + (end.G - start.G) * t);
        int b = (int)(start.B + (end.B - start.B) * t);
        return Color.FromArgb(r, g, b);
    }

    // Draws the snake using interpolated positions.
    void DrawSnakeInterpolated(Graphics g, List<PointF> prevSnake, List<Point> snake, Color baseColor, bool isPlayer, float alpha) {
        if (snake == null || snake.Count == 0)
            return;

        // Build a list of interpolated positions.
        List<PointF> interp = new List<PointF>();
        for (int i = 0; i < snake.Count; i++) {
            PointF from = i < prevSnake.Count ? prevSnake[i] : new PointF(snake[i].X, snake[i].Y);
            PointF to = new PointF(snake[i].X, snake[i].Y);
            interp.Add(Lerp(from, to, alpha));
        }

        float headRadius = cellSize * 0.8f;
        float tailRadius = cellSize * 0.4f;
        
        Color headColor = isPlayer ? GetRainbowColor(rainbowPhase) : baseColor;
        Color tailColor = isPlayer ? GetRainbowColor(rainbowPhase + 0.3f) : ControlPaint.Dark(baseColor);

        for (int i = 0; i < snake.Count; i++) {
            float t = snake.Count > 1 ? (float)i / (snake.Count - 1) : 0f;
            float radius = headRadius * (1 - t) + tailRadius * t;
            Color nodeColor = InterpolateColor(headColor, tailColor, t);
            float cx = interp[i].X * cellSize + cellSize / 2f;
            float cy = interp[i].Y * cellSize + cellSize / 2f;
            
            // Add glow effect for the player's snake.
            if (isPlayer) {
                using (GraphicsPath glowPath = CreateGlowPath(new PointF(cx, cy), radius, radius * 1.5f))
                using (PathGradientBrush glowBrush = new PathGradientBrush(glowPath)) {
                    Color glowColor = Color.FromArgb((int)(100 * glowIntensity), nodeColor.R, nodeColor.G, nodeColor.B);
                    glowBrush.CenterColor = glowColor;
                    glowBrush.SurroundColors = new Color[] { Color.FromArgb(0, nodeColor) };
                    g.FillPath(glowBrush, glowPath);
                }
            }

            RectangleF nodeRect = new RectangleF(cx - radius, cy - radius, radius * 2, radius * 2);
            using (PathGradientBrush innerGlow = new PathGradientBrush(new PointF[] {
                new PointF(cx - radius, cy - radius),
                new PointF(cx + radius, cy - radius),
                new PointF(cx + radius, cy + radius),
                new PointF(cx - radius, cy + radius)
            })) {
                innerGlow.CenterColor = Color.FromArgb(200, 255, 255, 255);
                innerGlow.SurroundColors = new Color[] { Color.FromArgb(0, 255, 255, 255) };
                g.FillEllipse(innerGlow, nodeRect);
            }
            using (SolidBrush brush = new SolidBrush(nodeColor))
                g.FillEllipse(brush, nodeRect);
            using (Pen pen = new Pen(Color.FromArgb(100, Color.White), 2))
                g.DrawEllipse(pen, nodeRect);

            // Enhanced decorations for the player's head.
            if (i == 0 && isPlayer) {
                float eyeRadius = radius * 0.3f;
                float pupilRadius = eyeRadius * 0.5f;
                PointF leftEyeCenter = new PointF(cx - radius * 0.4f, cy - radius * 0.4f);
                PointF rightEyeCenter = new PointF(cx + radius * 0.4f, cy - radius * 0.4f);
                DrawShinyEye(g, leftEyeCenter, eyeRadius, pupilRadius);
                DrawShinyEye(g, rightEyeCenter, eyeRadius, pupilRadius);

                // Draw a stylish hat with a gradient.
                PointF hatLeft = new PointF(cx - radius * 0.6f, cy - radius);
                PointF hatRight = new PointF(cx + radius * 0.6f, cy - radius);
                PointF hatTop = new PointF(cx, cy - radius - radius * 1.5f);
                PointF[] hatPoints = { hatLeft, hatTop, hatRight };
                using (LinearGradientBrush hatBrush = new LinearGradientBrush(
                    new Point((int)hatLeft.X, (int)hatLeft.Y),
                    new Point((int)hatRight.X, (int)hatRight.Y),
                    GetRainbowColor(rainbowPhase + 0.2f),
                    GetRainbowColor(rainbowPhase + 0.7f)))
                {
                    g.FillPolygon(hatBrush, hatPoints);
                    g.DrawPolygon(new Pen(Color.FromArgb(100, Color.White), 2), hatPoints);
                }
            }

            // Draw smooth connecting capsules between segments.
            if (i < snake.Count - 1) {
                float tNext = (float)(i + 1) / (snake.Count - 1);
                float nextRadius = headRadius * (1 - tNext) + tailRadius * tNext;
                Color nextColor = InterpolateColor(headColor, tailColor, tNext);
                PointF p1 = new PointF(cx, cy);
                PointF nextInterp = new PointF(interp[i + 1].X * cellSize + cellSize / 2f,
                                               interp[i + 1].Y * cellSize + cellSize / 2f);
                float dx = nextInterp.X - p1.X;
                float dy = nextInterp.Y - p1.Y;
                float angle = (float)Math.Atan2(dy, dx);
                PointF offset1 = new PointF(radius * (float)Math.Sin(angle), -radius * (float)Math.Cos(angle));
                PointF offset2 = new PointF(nextRadius * (float)Math.Sin(angle), -nextRadius * (float)Math.Cos(angle));
                using (GraphicsPath path = new GraphicsPath()) {
                    PointF p1a = new PointF(p1.X - offset1.X, p1.Y - offset1.Y);
                    PointF p2a = new PointF(nextInterp.X - offset2.X, nextInterp.Y - offset2.Y);
                    PointF p2b = new PointF(nextInterp.X + offset2.X, nextInterp.Y + offset2.Y);
                    PointF p1b = new PointF(p1.X + offset1.X, p1.Y + offset1.Y);
                    PointF[] capsulePts = new PointF[] { p1a, p2a, p2b, p1b };
                    path.AddPolygon(capsulePts);
                    if (Math.Abs(dx) < 0.001f && Math.Abs(dy) < 0.001f) {
                        using (SolidBrush solidBrush = new SolidBrush(nodeColor))
                            g.FillPath(solidBrush, path);
                    } else {
                        using (LinearGradientBrush lgBrush = new LinearGradientBrush(p1, nextInterp, nodeColor, nextColor))
                            g.FillPath(lgBrush, path);
                    }
                }
            }
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        using (var bgBrush = new LinearGradientBrush(ClientRectangle, Color.FromArgb(0, 0, 0), Color.FromArgb(32, 32, 32), 90F))
            e.Graphics.FillRectangle(bgBrush, ClientRectangle);
        base.OnPaint(e);
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        // Compute an interpolation factor between 0 and 1.
        float alpha = (float)(DateTime.Now - lastUpdateTime).TotalMilliseconds / logicTimer.Interval;
        if (alpha > 1f) alpha = 1f;

        DrawSnakeInterpolated(g, prevPlayerSnake, playerSnake, playerBaseColor, true, alpha);
        DrawSnakeInterpolated(g, prevEnemySnake, enemySnake, Color.Blue, false, alpha);

        // Draw foods with interpolated positions.
        foreach (var food in foods) {
            // Get previous position if available.
            Point prevPos = prevFoodPositions.ContainsKey(food.Id) ? prevFoodPositions[food.Id] : food.Position;
            PointF interpolated = Lerp(new PointF(prevPos.X, prevPos.Y), new PointF(food.Position.X, food.Position.Y), alpha);

            float cx = interpolated.X * cellSize + cellSize / 2f;
            float cy = interpolated.Y * cellSize + cellSize / 2f;

            if (food.IsMagnetic) {
                // Draw magnetic food (1.5x size, oscillating between red and white)
                float oscillation = (float)(Math.Sin(animationPhase * 2) * 0.5 + 0.5);
                Color magneticColor = InterpolateColor(Color.Red, Color.White, oscillation);
                float size = cellSize * 1.5f;
                RectangleF foodRect = new RectangleF(cx - size / 2, cy - size / 2, size, size);
                using (SolidBrush brush = new SolidBrush(magneticColor))
                    g.FillEllipse(brush, foodRect);
            }
            else if (food.IsSpecial) {
                Color oscillatingColor = GetRainbowColor(rainbowPhase + 0.5f);
                Rectangle foodRect = new Rectangle((int)(cx - cellSize), (int)(cy - cellSize), cellSize * 2, cellSize * 2);
                using (SolidBrush brush = new SolidBrush(oscillatingColor))
                    g.FillEllipse(brush, foodRect);
            }
            else {
                Rectangle foodRect = new Rectangle((int)(interpolated.X * cellSize), (int)(interpolated.Y * cellSize), cellSize, cellSize);
                using (SolidBrush brush = new SolidBrush(food.FoodColor))
                    g.FillEllipse(brush, foodRect);
            }
        }

        string scoreText = string.Format("Player: {0}    Enemy: {1}", playerScore, enemyScore);
        g.DrawString(scoreText, this.Font, Brushes.Black, 5, rows * cellSize + 5);
        if (enemySnake.Count > 0)
            g.DrawString("Enemy Pos: " + enemySnake[0], this.Font, Brushes.Blue, 5, rows * cellSize + 20);
    }
}

public static class Program {
    [STAThread]
    public static void Main() {
        Application.EnableVisualStyles();
        Application.Run(new GameForm());
    }
}
