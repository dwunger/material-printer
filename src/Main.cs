using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

//
// MainMenuForm: The startup screen with instructions, changelog, and start button.
//
public class MainMenuForm : Form {
    public MainMenuForm() {
        this.Text = "Snek Menu - Version 1.1.1";
        this.ClientSize = new Size(600, 400);
        this.StartPosition = FormStartPosition.CenterScreen;
        this.FormBorderStyle = FormBorderStyle.FixedSingle;
        this.MaximizeBox = false;

        // Instructions Label
        Label instructionsLabel = new Label();
        instructionsLabel.Text = "Controls:\n" +
            "- Move snake with mouse (WASD/Arrow keys override).\n" +
            "- Press Space or hold mouse down to boost (costs 1 segment/tick).\n" +
            "- Magnetic and special food trigger unique effects.";
        instructionsLabel.Location = new Point(20, 20);
        instructionsLabel.Size = new Size(280, 150);
        instructionsLabel.Font = new Font("Arial", 10);
        instructionsLabel.AutoSize = false;

        // Changelog side pane with updated log
        GroupBox changelogBox = new GroupBox();
        changelogBox.Text = "Changelog";
        changelogBox.Location = new Point(320, 20);
        changelogBox.Size = new Size(250, 300);
        Label changelogLabel = new Label();
        changelogLabel.Text = "Version 1.1.1:\n" +
            "- Randomized normal food color and added transparency.\n" +
            "- Added new special food: BigHead. I haven't decided on its effect yet.";
        changelogLabel.Location = new Point(10, 20);
        changelogLabel.Size = new Size(230, 270);
        changelogLabel.Font = new Font("Arial", 9);
        changelogLabel.AutoSize = false;
        changelogLabel.TextAlign = ContentAlignment.TopLeft;
        changelogBox.Controls.Add(changelogLabel);

        // Start Button
        Button startButton = new Button();
        startButton.Text = "Start Game";
        startButton.Location = new Point(250, 350);
        startButton.Size = new Size(100, 40);
        startButton.Click += (s, e) => {
            GameForm gameForm = new GameForm();
            gameForm.StartPosition = FormStartPosition.CenterScreen;
            gameForm.Show();
            this.Hide();
        };

        this.Controls.Add(instructionsLabel);
        this.Controls.Add(changelogBox);
        this.Controls.Add(startButton);
    }
}

//
// GameForm: The main game with circular boundary, camera tracking, and multiple enemy snakes.
//
public class GameForm : Form {
    Timer logicTimer;
    Timer renderTimer;
    List<PointF> playerSnake;
    List<PointF> prevPlayerSnake;

    // Multiple enemy snakes
    List<EnemySnake> enemySnakes;

    Dictionary<int, PointF> prevFoodPositions = new Dictionary<int, PointF>();
    List<Food> foods = new List<Food>();
    int cellSize = 10, cols = 40, rows = 40;

    // Map boundary (circular) variables – center is player's start
    PointF mapCenter;
    float mapRadius;

    // Movement vector for player
    float playerVX = 1f, playerVY = 0f;

    int playerScore = 0;
    Random rand = new Random();
    float animationPhase = 0f;
    Color playerBaseColor = Color.Green;
    bool gameStarted = false;
    bool keyboardOverride = false;
    Point currentMousePosition;

    // Boosting flag
    bool isBoosting = false;
    float baseSpeed = 1.0f;

    float glowIntensity = 1.0f;
    float rainbowPhase = 0f;
    const float RAINBOW_SPEED = 0.05f;

    DateTime lastUpdateTime;

    int playerMagnetTicks = 0;
    int superFoodTicks = 0;
    int bigHeadTicks = 0; // Ticks remaining for BigHead effect

    // Collision threshold (in grid units)
    const float collisionThreshold = 0.7f;

    // Food struct using float positions.
    // Added IsBigHead flag to distinguish BigHead food.
    private struct Food {
        public int Id;
        public PointF Position;
        public bool IsSpecial;
        public bool IsMagnetic;
        public bool IsBigHead;
        public Color FoodColor;
    }
    int nextFoodId = 0;

    // Enemy snake class encapsulating segments, velocity, color, and name tag.
    private class EnemySnake {
        public List<PointF> Segments;
        public List<PointF> PrevSegments;
        public float VX, VY;
        public Color BaseColor;
        public string Name;
        public int MagnetTicks;
        public int Score;

        public EnemySnake(PointF spawn, Color baseColor, string name) {
            Segments = new List<PointF> { spawn };
            PrevSegments = new List<PointF> { spawn };
            VX = 1f;
            VY = 0f;
            BaseColor = baseColor;
            Name = name;
            MagnetTicks = 0;
            Score = 0;
        }
    }

    public GameForm() {
        // The visible area is defined by cols x rows.
        this.ClientSize = new Size(cols * cellSize, rows * cellSize + 40);
        this.DoubleBuffered = true;
        this.Text = "Snek - Version 1.1.0";
        this.KeyPreview = true;

        // Set up the circular map – center at player's start and radius ~ 3x visible grid.
        mapCenter = new PointF(cols / 2f, rows / 2f);
        mapRadius = Math.Max(cols, rows) * 1.5f; // For cols=40, radius=60

        // Initialize player snake at center.
        playerSnake = new List<PointF> { new PointF(cols / 2f, rows / 2f) };
        prevPlayerSnake = playerSnake.Select(p => new PointF(p.X, p.Y)).ToList();

        // Initialize multiple enemy snakes with distinct colors and name tags.
        enemySnakes = new List<EnemySnake>();
        enemySnakes.Add(new EnemySnake(GenerateRandomPositionInMap(), Color.Blue, "Blue Bomber"));
        enemySnakes.Add(new EnemySnake(GenerateRandomPositionInMap(), Color.Purple, "Violet Viper"));
        enemySnakes.Add(new EnemySnake(GenerateRandomPositionInMap(), Color.Orange, "Orange Obliterator"));

        GenerateFoods();

        logicTimer = new Timer { Interval = 100 };
        logicTimer.Tick += (s, e) => UpdateGame();
        renderTimer = new Timer { Interval = 16 };
        renderTimer.Tick += (s, e) => Invalidate();

        this.MouseDown += (s, e) => { 
            keyboardOverride = false; 
            if (e.Button == MouseButtons.Left) 
                isBoosting = true; 
            if (!gameStarted && e.Button == MouseButtons.Left) {
                gameStarted = true;
                lastUpdateTime = DateTime.Now;
                logicTimer.Start();
                renderTimer.Start();
            }
        };
        this.MouseUp += (s, e) => { if (e.Button == MouseButtons.Left) isBoosting = false; };
        this.MouseMove += (s, e) => { if (!keyboardOverride) currentMousePosition = e.Location; };
        this.KeyDown += GameForm_KeyDown;
        this.KeyUp += (s, e) => { if (e.KeyCode == Keys.Space) isBoosting = false; };
    }

    private PointF Lerp(PointF a, PointF b, float t) {
        return new PointF(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t);
    }

    private float Distance(PointF a, PointF b) {
        float dx = a.X - b.X, dy = a.Y - b.Y;
        return (float)Math.Sqrt(dx * dx + dy * dy);
    }

    private GraphicsPath CreateGlowPath(PointF center, float radius, float glowSize) {
        GraphicsPath path = new GraphicsPath();
        for (float size = radius; size <= radius + glowSize; size += glowSize / 4)
            path.AddEllipse(center.X - size, center.Y - size, size * 2, size * 2);
        return path;
    }

    private Color GetRainbowColor(float phase) {
        float frequency = 2.0f * (float)Math.PI;
        int r = (int)(Math.Sin(frequency * phase + 0) * 127 + 128);
        int g = (int)(Math.Sin(frequency * phase + 2) * 127 + 128);
        int b = (int)(Math.Sin(frequency * phase + 4) * 127 + 128);
        return Color.FromArgb(r, g, b);
    }

    private void DrawShinyEye(Graphics g, PointF center, float eyeRadius, float pupilRadius) {
        RectangleF eyeRect = new RectangleF(center.X - eyeRadius, center.Y - eyeRadius, eyeRadius * 2, eyeRadius * 2);
        g.FillEllipse(Brushes.White, eyeRect);
        using (PathGradientBrush shine = new PathGradientBrush(new PointF[] {
            new PointF(center.X - eyeRadius * 0.7f, center.Y - eyeRadius * 0.7f),
            new PointF(center.X + eyeRadius * 0.7f, center.Y - eyeRadius * 0.7f),
            new PointF(center.X, center.Y + eyeRadius * 0.7f)
        })) {
            shine.CenterColor = Color.FromArgb(150, 255, 255, 255);
            shine.SurroundColors = new Color[] { Color.FromArgb(0, 255, 255, 255) };
            g.FillEllipse(shine, eyeRect);
        }
        RectangleF pupilRect = new RectangleF(center.X - pupilRadius, center.Y - pupilRadius, pupilRadius * 2, pupilRadius * 2);
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
        switch (e.KeyCode) {
            case Keys.Up:
            case Keys.W:
                playerVX = 0; playerVY = -1; break;
            case Keys.Down:
            case Keys.S:
                playerVX = 0; playerVY = 1; break;
            case Keys.Left:
            case Keys.A:
                playerVX = -1; playerVY = 0; break;
            case Keys.Right:
            case Keys.D:
                playerVX = 1; playerVY = 0; break;
            case Keys.Space:
                isBoosting = true; break;
        }
    }

    // Determines if a point is outside the circular map boundary.
    bool IsOutOfBounds(PointF p) {
        return Distance(p, mapCenter) > mapRadius;
    }

    // Generates a random position within the circular map.
    private PointF GenerateRandomPositionInMap() {
        double angle = rand.NextDouble() * 2 * Math.PI;
        double r = Math.Sqrt(rand.NextDouble()) * mapRadius;
        float x = (float)(mapCenter.X + r * Math.Cos(angle));
        float y = (float)(mapCenter.Y + r * Math.Sin(angle));
        return new PointF(x, y);
    }

    // Update game logic.
    void UpdateGame() {
        float pickupThreshold = 1.2f;

        prevPlayerSnake = playerSnake.Select(p => new PointF(p.X, p.Y)).ToList();
        foreach (var enemy in enemySnakes)
            enemy.PrevSegments = enemy.Segments.Select(p => new PointF(p.X, p.Y)).ToList();
        var newPrevFoodPositions = new Dictionary<int, PointF>();
        foreach (var food in foods)
            newPrevFoodPositions[food.Id] = food.Position;
        prevFoodPositions = newPrevFoodPositions;

        animationPhase += 0.2f;
        if (animationPhase > Math.PI * 2) animationPhase -= (float)(Math.PI * 2);
        rainbowPhase += RAINBOW_SPEED;
        if (rainbowPhase > 1.0f) rainbowPhase -= 1.0f;
        glowIntensity = 0.7f + (float)Math.Sin(animationPhase) * 0.3f;

        // --- Player Update ---
        PointF head = playerSnake[0];
        float candidateVX, candidateVY;
        if (!keyboardOverride) {
            // Translate mouse position into world coordinates relative to player head.
            float targetX = currentMousePosition.X / (float)cellSize + (head.X - (ClientSize.Width / (2f * cellSize)));
            float targetY = currentMousePosition.Y / (float)cellSize + (head.Y - (ClientSize.Height / (2f * cellSize)));
            float diffX = targetX - head.X;
            float diffY = targetY - head.Y;
            float len = (float)Math.Sqrt(diffX * diffX + diffY * diffY);
            if (len > 0.0001f) {
                candidateVX = diffX / len;
                candidateVY = diffY / len;
            } else {
                candidateVX = playerVX;
                candidateVY = playerVY;
            }
        } else {
            candidateVX = playerVX;
            candidateVY = playerVY;
        }
        playerVX = candidateVX;
        playerVY = candidateVY;
        float boostMult = (isBoosting && playerSnake.Count > 1) ? 1.5f : 1.0f;
        PointF newHead = new PointF(head.X + playerVX * baseSpeed * boostMult, head.Y + playerVY * baseSpeed * boostMult);

        // Use a larger pickup threshold if BigHead effect is active.
        float effectivePickupThreshold = (bigHeadTicks > 0 ? pickupThreshold * 5 : pickupThreshold);
        if (IsOutOfBounds(newHead) ||
            (playerSnake.Count >= 3 && playerSnake.Skip(2).Any(p => Distance(p, newHead) < collisionThreshold)) ||
            enemySnakes.Any(enemy => enemy.Segments.Skip(1).Any(p => Distance(p, newHead) < collisionThreshold))) {
            logicTimer.Stop();
            renderTimer.Stop();
            MessageBox.Show("Game Over! Your Score: " + playerScore);
            Application.Exit();
            return;
        }
        playerSnake.Insert(0, newHead);
        int foodIndex = foods.FindIndex(f => Distance(newHead, f.Position) < effectivePickupThreshold);
        if (foodIndex != -1) {
            Food eaten = foods[foodIndex];
            if (eaten.IsMagnetic) {
                playerScore += 20;
                PointF tail = playerSnake[playerSnake.Count - 1];
                for (int i = 0; i < 3; i++) playerSnake.Add(tail);
                playerMagnetTicks = 20;
            } else if (eaten.IsBigHead) {
                playerScore += 40;
                PointF tail = playerSnake[playerSnake.Count - 1];
                for (int i = 0; i < 4; i++) playerSnake.Add(tail);
                bigHeadTicks = 150;
            } else if (eaten.IsSpecial) {
                playerScore += 100;
                PointF tail = playerSnake[playerSnake.Count - 1];
                for (int i = 0; i < 30; i++) playerSnake.Add(tail);
                superFoodTicks = 100;
            } else {
                playerScore += 10;
            }
            foods.RemoveAt(foodIndex);
        } else {
            playerSnake.RemoveAt(playerSnake.Count - 1);
        }
        if (isBoosting && playerSnake.Count > 1)
            playerSnake.RemoveAt(playerSnake.Count - 1);

        // --- Enemy Update ---
        if (foods.Count == 0) GenerateFoods();

        foreach (var enemy in enemySnakes) {
            PointF enemyHead = enemy.Segments[0];
            if (!foods.Any()) { GenerateFoods(); }
            if (!foods.Any()) continue;
            Food targetFood = foods.OrderBy(f => Distance(f.Position, enemyHead)).First();
            float diffEx = targetFood.Position.X - enemyHead.X;
            float diffEy = targetFood.Position.Y - enemyHead.Y;
            float lenE = (float)Math.Sqrt(diffEx * diffEx + diffEy * diffEy);
            float desiredVX = (lenE > 0.0001f) ? diffEx / lenE : enemy.VX;
            float desiredVY = (lenE > 0.0001f) ? diffEy / lenE : enemy.VY;

            bool safeMoveFound = false;
            float finalVX = desiredVX, finalVY = desiredVY;
            float baseAngle = (float)Math.Atan2(desiredVY, desiredVX);
            float[] angleOffsets = new float[] { 0, 15, -15, 30, -30, 45, -45 };
            foreach (var offset in angleOffsets) {
                float radOffset = offset * (float)Math.PI / 180f;
                float testAngle = baseAngle + radOffset;
                float testVX = (float)Math.Cos(testAngle);
                float testVY = (float)Math.Sin(testAngle);
                PointF testHead = new PointF(enemyHead.X + testVX * baseSpeed, enemyHead.Y + testVY * baseSpeed);
                if (IsEnemyMoveSafe(enemy, testHead)) {
                    finalVX = testVX;
                    finalVY = testVY;
                    safeMoveFound = true;
                    break;
                }
            }
            if (!safeMoveFound) {
                RespawnEnemy(enemy);
                continue;
            }

            enemy.VX = finalVX;
            enemy.VY = finalVY;
            PointF newEnemyHead = new PointF(enemyHead.X + enemy.VX * baseSpeed, enemyHead.Y + enemy.VY * baseSpeed);
            if (!IsEnemyMoveSafe(enemy, newEnemyHead)) {
                RespawnEnemy(enemy);
                continue;
            }
            enemy.Segments.Insert(0, newEnemyHead);

            int enemyFoodIndex = foods.FindIndex(f => Distance(newEnemyHead, f.Position) < pickupThreshold);
            if (enemyFoodIndex != -1) {
                Food eaten = foods[enemyFoodIndex];
                if (eaten.IsMagnetic) {
                    enemy.Score += 20;
                    PointF tail = enemy.Segments[enemy.Segments.Count - 1];
                    for (int i = 0; i < 3; i++) enemy.Segments.Add(tail);
                    enemy.MagnetTicks = 20;
                } else if (eaten.IsBigHead) {
                    enemy.Score += 40;
                    PointF tail = enemy.Segments[enemy.Segments.Count - 1];
                    for (int i = 0; i < 4; i++) enemy.Segments.Add(tail);
                    // Enemies do not get a head expansion effect.
                } else if (eaten.IsSpecial) {
                    enemy.Score += 100;
                    PointF tail = enemy.Segments[enemy.Segments.Count - 1];
                    for (int i = 0; i < 10; i++) enemy.Segments.Add(tail);
                } else {
                    enemy.Score += 10;
                }
                foods.RemoveAt(enemyFoodIndex);
            } else {
                enemy.Segments.RemoveAt(enemy.Segments.Count - 1);
            }

            if (enemy.MagnetTicks > 0) enemy.MagnetTicks--;
        }

        // --- Magnetic Food Attraction ---
        for (int i = 0; i < foods.Count; i++) {
            bool playerActive = playerMagnetTicks > 0;
            bool enemyActive = enemySnakes.Any(e => e.MagnetTicks > 0);
            if (!playerActive && !enemyActive)
                continue;
            PointF target;
            if (playerActive && enemyActive) {
                float playerDist = Distance(foods[i].Position, playerSnake[0]);
                var activeEnemies = enemySnakes.Where(e => e.MagnetTicks > 0).ToList();
                float enemyDist = activeEnemies.Min(e => Distance(foods[i].Position, e.Segments[0]));
                target = (playerDist <= enemyDist) ? playerSnake[0] : activeEnemies.First(e => Distance(foods[i].Position, e.Segments[0]) == enemyDist).Segments[0];
            } else if (playerActive) {
                target = playerSnake[0];
            } else {
                target = enemySnakes.First(e => e.MagnetTicks > 0).Segments[0];
            }

            float attractionSpeed = 0.5f;
            float diffX = target.X - foods[i].Position.X;
            float diffY = target.Y - foods[i].Position.Y;
            float dist = (float)Math.Sqrt(diffX * diffX + diffY * diffY);
            if (dist > 0.0001f) {
                diffX = attractionSpeed * diffX / dist;
                diffY = attractionSpeed * diffY / dist;
            }
            Food f = foods[i];
            f.Position = new PointF(f.Position.X + diffX, f.Position.Y + diffY);
            foods[i] = f;
        }
        if (playerMagnetTicks > 0) playerMagnetTicks--;
        if (superFoodTicks > 0) superFoodTicks--;
        if (bigHeadTicks > 0) bigHeadTicks--;

        if (rand.NextDouble() < 0.05) GenerateFoods();
        lastUpdateTime = DateTime.Now;
    }

    // Checks if an enemy’s candidate move avoids collisions.
    private bool IsEnemyMoveSafe(EnemySnake enemy, PointF newHead) {
        if (IsOutOfBounds(newHead)) return false;
        if (enemy.Segments.Count >= 3 && enemy.Segments.Skip(2).Any(p => Distance(p, newHead) < collisionThreshold))
            return false;
        if (playerSnake.Count >= 2 && playerSnake.Skip(1).Any(p => Distance(p, newHead) < collisionThreshold))
            return false;
        foreach (var other in enemySnakes) {
            if (other == enemy) continue;
            if (other.Segments.Any(p => Distance(p, newHead) < collisionThreshold))
                return false;
        }
        return true;
    }

    // Respawns an enemy snake.
    private void RespawnEnemy(EnemySnake enemy) {
        enemy.Segments.Clear();
        PointF p;
        do {
            p = GenerateRandomPositionInMap();
        } while (playerSnake.Any(q => Distance(q, p) < 0.5f) || foods.Any(f => Distance(f.Position, p) < 0.5f));
        enemy.Segments.Add(p);
        enemy.Score /= 2;
        enemy.VX = 1f; enemy.VY = 0f;
        enemy.MagnetTicks = 0;
    }

    // Generates food at random positions.
    void GenerateFoods() {
        int count = 10; 
        for (int i = 0; i < count; i++) {
            Food newFood;
            do {
                newFood.Position = GenerateRandomPositionInMap();
            } while (playerSnake.Any(p => Distance(p, newFood.Position) < 0.5f) ||
                     enemySnakes.Any(e => e.Segments.Any(p => Distance(p, newFood.Position) < 0.5f)) ||
                     foods.Any(f => Distance(f.Position, newFood.Position) < 0.5f));
            double bigHeadChance = 0.020;
            double magneticChance = 0.015;
            double specialChance = 0.075;
            if (rand.NextDouble() < bigHeadChance) {
                newFood.IsBigHead = true;
                newFood.IsSpecial = false;
                newFood.IsMagnetic = false;
                newFood.FoodColor = Color.Empty;
            }
            else if (rand.NextDouble() < magneticChance) {
                newFood.IsMagnetic = true;
                newFood.IsSpecial = false;
                newFood.IsBigHead = false;
                newFood.FoodColor = Color.Red;
            }
            else if (rand.NextDouble() < specialChance) {
                newFood.IsSpecial = true;
                newFood.IsMagnetic = false;
                newFood.IsBigHead = false;
                newFood.FoodColor = Color.Empty;
            } else {
                newFood.IsSpecial = false;
                newFood.IsMagnetic = false;
                newFood.IsBigHead = false;
                newFood.FoodColor = Color.FromArgb(191, rand.Next(256), rand.Next(256), rand.Next(256));
            }
            newFood.Id = nextFoodId++;
            foods.Add(newFood);
        }
    }

    // Interpolates between two colors.
    Color InterpolateColor(Color start, Color end, float t) {
        int r = (int)(start.R + (end.R - start.R) * t);
        int g = (int)(start.G + (end.G - start.G) * t);
        int b = (int)(start.B + (end.B - start.B) * t);
        return Color.FromArgb(r, g, b);
    }

    // Draws a snake with interpolation.
    void DrawSnakeInterpolated(Graphics g, List<PointF> prevSnake, List<PointF> snake, Color baseColor, bool isPlayer, float alpha) {
        if (snake == null || snake.Count == 0) return;
        List<PointF> interp = new List<PointF>();
        for (int i = 0; i < snake.Count; i++) {
            PointF from = i < prevSnake.Count ? prevSnake[i] : snake[i];
            PointF to = snake[i];
            interp.Add(Lerp(from, to, alpha));
        }
        float headRadius = cellSize * 0.8f;
        float tailRadius = cellSize * 0.4f;
        Color headColor = (isPlayer && superFoodTicks > 0) ? GetRainbowColor(rainbowPhase) : (isPlayer ? playerBaseColor : baseColor);
        Color tailColor = (isPlayer && superFoodTicks > 0) ? GetRainbowColor(rainbowPhase + 0.3f) : (isPlayer ? ControlPaint.Dark(playerBaseColor) : ControlPaint.Dark(baseColor));
        for (int i = 0; i < snake.Count; i++) {
            float t = snake.Count > 1 ? (float)i / (snake.Count - 1) : 0f;
            float radius = headRadius * (1 - t) + tailRadius * t;
            // Apply BigHead effect to the player's head.
            if (isPlayer && i == 0 && bigHeadTicks > 0) {
                float elapsed = 150 - bigHeadTicks;
                float tNorm = elapsed / 150f;
                float scale = 1 + 4 * (float)Math.Sin(Math.PI * tNorm);
                radius *= scale;
            }
            Color nodeColor = InterpolateColor(headColor, tailColor, t);
            float cx = interp[i].X * cellSize + cellSize / 2f;
            float cy = interp[i].Y * cellSize + cellSize / 2f;
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
            if (i == 0 && isPlayer) {
                float eyeRadius = radius * 0.3f;
                float pupilRadius = eyeRadius * 0.5f;
                PointF leftEyeCenter = new PointF(cx - radius * 0.4f, cy - radius * 0.4f);
                PointF rightEyeCenter = new PointF(cx + radius * 0.4f, cy - radius * 0.4f);
                DrawShinyEye(g, leftEyeCenter, eyeRadius, pupilRadius);
                DrawShinyEye(g, rightEyeCenter, eyeRadius, pupilRadius);
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
                        // Instead of creating a new LinearGradientBrush per segment,
                        // compute an average color and use a SolidBrush.
                        Color avgColor = InterpolateColor(nodeColor, nextColor, 0.5f);
                        using (SolidBrush solidBrush = new SolidBrush(avgColor))
                            g.FillPath(solidBrush, path);
                    }
                }
            }
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        // Use the same interpolation factor as used for snake drawing.
        float alpha = (float)(DateTime.Now - lastUpdateTime).TotalMilliseconds / logicTimer.Interval;
        if (alpha > 1f) alpha = 1f;
        // Interpolate the player's head position to smooth camera movement.
        PointF interpolatedPlayerHead = Lerp(prevPlayerSnake[0], playerSnake[0], alpha);
        PointF playerHeadPixel = new PointF(interpolatedPlayerHead.X * cellSize, interpolatedPlayerHead.Y * cellSize);
        PointF cameraOffset = new PointF(playerHeadPixel.X - ClientSize.Width / 2f, playerHeadPixel.Y - ClientSize.Height / 2f);

        // Apply camera transformation so that the snake head is always at the center.
        g.TranslateTransform(-cameraOffset.X, -cameraOffset.Y);

        // Draw grid background.
        float leftWorld = cameraOffset.X;
        float topWorld = cameraOffset.Y;
        float rightWorld = leftWorld + ClientSize.Width;
        float bottomWorld = topWorld + ClientSize.Height;
        int startCol = (int)Math.Floor(leftWorld / cellSize);
        int endCol = (int)Math.Ceiling(rightWorld / cellSize);
        int startRow = (int)Math.Floor(topWorld / cellSize);
        int endRow = (int)Math.Ceiling(bottomWorld / cellSize);
        for (int i = startCol; i <= endCol; i++) {
            float x = i * cellSize;
            g.DrawLine(Pens.Gray, x, topWorld, x, bottomWorld);
        }
        for (int j = startRow; j <= endRow; j++) {
            float y = j * cellSize;
            g.DrawLine(Pens.Gray, leftWorld, y, rightWorld, y);
        }
        g.DrawRectangle(Pens.Gray, leftWorld, topWorld, ClientSize.Width, ClientSize.Height);

        // Draw the circular map boundary.
        float boundaryDiameter = mapRadius * 2 * cellSize;
        RectangleF boundaryRect = new RectangleF((mapCenter.X - mapRadius) * cellSize, (mapCenter.Y - mapRadius) * cellSize, boundaryDiameter, boundaryDiameter);
        g.DrawEllipse(Pens.Yellow, boundaryRect);

        // Draw the player snake.
        DrawSnakeInterpolated(g, prevPlayerSnake, playerSnake, playerBaseColor, true, alpha);

        // Draw each enemy snake.
        foreach (var enemy in enemySnakes)
            DrawSnakeInterpolated(g, enemy.PrevSegments, enemy.Segments, enemy.BaseColor, false, alpha);

        // Draw foods.
        foreach (var food in foods) {
            PointF prevPos = prevFoodPositions.ContainsKey(food.Id) ? prevFoodPositions[food.Id] : food.Position;
            PointF interpolated = Lerp(prevPos, food.Position, alpha);

            float cx = interpolated.X * cellSize + cellSize / 2f;
            float cy = interpolated.Y * cellSize + cellSize / 2f;

            if (food.IsBigHead) {
                // BigHead food is drawn a bit larger with a cyan-magenta gradient.
                float size = cellSize * 2.5f;
                RectangleF foodRect = new RectangleF(cx - size/2, cy - size/2, size, size);
                using (GraphicsPath path = new GraphicsPath()) {
                    path.AddEllipse(foodRect);
                    using (PathGradientBrush pgb = new PathGradientBrush(path)) {
                        pgb.CenterColor = Color.Cyan;
                        pgb.SurroundColors = new Color[] { Color.Magenta };
                        g.FillEllipse(pgb, foodRect);
                    }
                }
            }
            else if (food.IsMagnetic) {
                float oscillation = (float)(Math.Sin(animationPhase * 2) * 0.5 + 0.5);
                Color magneticColor = InterpolateColor(Color.Red, Color.White, oscillation);
                float size = cellSize * 1.5f;
                RectangleF foodRect = new RectangleF(cx - size / 2, cy - size / 2, size, size);
                using (SolidBrush brush = new SolidBrush(magneticColor))
                    g.FillEllipse(brush, foodRect);
            }
            else if (food.IsSpecial) {
                Color oscillatingColor = GetRainbowColor(rainbowPhase + 0.5f);
                RectangleF foodRect = new RectangleF(cx - cellSize, cy - cellSize, cellSize * 2, cellSize * 2);
                using (SolidBrush brush = new SolidBrush(oscillatingColor))
                    g.FillEllipse(brush, foodRect);
            }
            else {
                RectangleF foodRect = new RectangleF(interpolated.X * cellSize, interpolated.Y * cellSize, cellSize, cellSize);
                using (SolidBrush brush = new SolidBrush(food.FoodColor))
                    g.FillEllipse(brush, foodRect);
            }
        }

        // Draw enemy name tags.
        foreach (var enemy in enemySnakes) {
            PointF enemyHead = enemy.Segments[0];
            PointF enemyHeadPixel = new PointF(enemyHead.X * cellSize, enemyHead.Y * cellSize);
            PointF screenPos = new PointF(enemyHeadPixel.X - cameraOffset.X, enemyHeadPixel.Y - cameraOffset.Y);
            g.ResetTransform();
            g.DrawString(enemy.Name, this.Font, Brushes.Black, screenPos);
            g.TranslateTransform(-cameraOffset.X, -cameraOffset.Y);
        }

        // Reset transform and draw UI elements.
        g.ResetTransform();
        string scoreText = string.Format("Player: {0}", playerScore);
        g.DrawString(scoreText, this.Font, Brushes.Black, 5, ClientSize.Height - 35);
    }
}

//
// Program: Entry point.
//
public static class Program {
    [STAThread]
    public static void Main() {
        Application.EnableVisualStyles();
        Application.Run(new MainMenuForm());
    }
}
