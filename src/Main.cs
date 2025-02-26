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
        this.Text = "Snek Menu - Version 1.0.10";
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

        // Changelog side pane
        GroupBox changelogBox = new GroupBox();
        changelogBox.Text = "Changelog";
        changelogBox.Location = new Point(320, 20);
        changelogBox.Size = new Size(250, 300);
        Label changelogLabel = new Label();
        changelogLabel.Text = "Version 1.0.10:\n" +
            "- On enemy death, each segment becomes base food.\n" +
            "- Snakes move freely using float positions (not grid-locked).\n" +
            "- Added weak magnetism near snake heads.\n" +
            "- Boosting now removes one segment per tick.\n" +
            "- Lowered food spawn probability with per-tick chance.\n" +
            "- Grid background with gray boundaries added.\n" +
            "- Rainbow effect on player triggered by super food.";
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
// GameForm: The main game (version 1.0.10) with grid background, improved food pickup, and super-food-triggered rainbow effect.
//
public class GameForm : Form {
    Timer logicTimer;
    Timer renderTimer;
    List<PointF> playerSnake;
    List<PointF> enemySnake;
    List<PointF> prevPlayerSnake;
    List<PointF> prevEnemySnake;
    
    Dictionary<int, PointF> prevFoodPositions = new Dictionary<int, PointF>();
    List<Food> foods = new List<Food>();
    int cellSize = 10, cols = 40, rows = 40;
    
    // Movement vectors
    float playerVX = 1f, playerVY = 0f;
    float enemyVX = 1f, enemyVY = 0f;
    
    int playerScore = 0, enemyScore = 0;
    Random rand = new Random();
    float animationPhase = 0f;
    Color playerBaseColor = Color.Green;
    bool gameStarted = false;
    bool keyboardOverride = false;
    Point currentMousePosition;
    
    // Boosting flag
    bool isBoosting = false;
    float baseSpeed = 1.0f; // Increased speed

    float glowIntensity = 1.0f;
    float rainbowPhase = 0f;
    const float RAINBOW_SPEED = 0.05f;
    
    DateTime lastUpdateTime;
    
    int playerMagnetTicks = 0, enemyMagnetTicks = 0;
    // New: superFoodTicks triggers rainbow effect on player when > 0
    int superFoodTicks = 0;
    
    // Food struct using float positions
    private struct Food {
        public int Id;
        public PointF Position;
        public bool IsSpecial;
        public bool IsMagnetic;
        public Color FoodColor;
    }
    int nextFoodId = 0;
    
    public GameForm() {
        this.ClientSize = new Size(cols * cellSize, rows * cellSize + 40);
        this.DoubleBuffered = true;
        this.Text = "Snek - Version 1.0.10";
        this.KeyPreview = true;
        
        // Initialize snakes
        playerSnake = new List<PointF> { new PointF(cols / 2f, rows / 2f) };
        enemySnake = new List<PointF> { new PointF(cols / 4f, rows / 4f) };
        prevPlayerSnake = playerSnake.Select(p => new PointF(p.X, p.Y)).ToList();
        prevEnemySnake = enemySnake.Select(p => new PointF(p.X, p.Y)).ToList();
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
    
    void UpdateGame() {
        prevPlayerSnake = playerSnake.Select(p => new PointF(p.X, p.Y)).ToList();
        prevEnemySnake = enemySnake.Select(p => new PointF(p.X, p.Y)).ToList();
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
            float targetX = currentMousePosition.X / (float)cellSize;
            float targetY = currentMousePosition.Y / (float)cellSize;
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
        // Skip immediate segment (index 1) in self-collision check.
        if (IsOutOfBounds(newHead) ||
            (playerSnake.Count >= 3 && playerSnake.Skip(2).Any(p => Distance(p, newHead) < 0.5f)) ||
            enemySnake.Skip(1).Any(p => Distance(p, newHead) < 0.5f)) {
            logicTimer.Stop();
            renderTimer.Stop();
            MessageBox.Show("Game Over! Your Score: " + playerScore);
            Application.Exit();
            return;
        }
        playerSnake.Insert(0, newHead);
        // Use a more forgiving pickup radius
        float pickupThreshold = 1.2f;
        int foodIndex = foods.FindIndex(f => Distance(newHead, f.Position) < pickupThreshold);
        if (foodIndex != -1) {
            Food eaten = foods[foodIndex];
            if (eaten.IsMagnetic) {
                playerScore += 20;
                PointF tail = playerSnake[playerSnake.Count - 1];
                for (int i = 0; i < 3; i++) playerSnake.Add(tail);
                playerMagnetTicks = 100;
            } else if (eaten.IsSpecial) {
                playerScore += 100;
                PointF tail = playerSnake[playerSnake.Count - 1];
                for (int i = 0; i < 30; i++) playerSnake.Add(tail);
                // Trigger rainbow effect via super food
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
        PointF enemyHead = enemySnake[0];
        Food targetFood = foods.OrderBy(f => Distance(f.Position, enemyHead)).First();
        float diffEx = targetFood.Position.X - enemyHead.X;
        float diffEy = targetFood.Position.Y - enemyHead.Y;
        float lenE = (float)Math.Sqrt(diffEx * diffEx + diffEy * diffEy);
        if (lenE > 0.0001f) {
            enemyVX = diffEx / lenE;
            enemyVY = diffEy / lenE;
        }
        PointF newEnemyHead = new PointF(enemyHead.X + enemyVX * baseSpeed, enemyHead.Y + enemyVY * baseSpeed);
        if (IsOutOfBounds(newEnemyHead) ||
            (enemySnake.Count >= 3 && enemySnake.Skip(2).Any(p => Distance(p, newEnemyHead) < 0.5f)) ||
            playerSnake.Skip(1).Any(p => Distance(p, newEnemyHead) < 0.5f)) {
            foreach (var seg in enemySnake) {
                Food newFood;
                newFood.Position = seg;
                newFood.IsMagnetic = false;
                newFood.IsSpecial = false;
                newFood.FoodColor = Color.Red;
                newFood.Id = nextFoodId++;
                foods.Add(newFood);
            }
            RespawnEnemy();
        } else {
            enemySnake.Insert(0, newEnemyHead);
            int enemyFoodIndex = foods.FindIndex(f => Distance(newEnemyHead, f.Position) < pickupThreshold);
            if (enemyFoodIndex != -1) {
                Food eaten = foods[enemyFoodIndex];
                if (eaten.IsMagnetic) {
                    enemyScore += 20;
                    PointF tail = enemySnake[enemySnake.Count - 1];
                    for (int i = 0; i < 3; i++) enemySnake.Add(tail);
                    enemyMagnetTicks = 100;
                } else if (eaten.IsSpecial) {
                    enemyScore += 100;
                    PointF tail = enemySnake[enemySnake.Count - 1];
                    for (int i = 0; i < 10; i++) enemySnake.Add(tail);
                } else {
                    enemyScore += 10;
                }
                foods.RemoveAt(enemyFoodIndex);
            } else {
                enemySnake.RemoveAt(enemySnake.Count - 1);
            }
        }
        
        // --- Magnetic Food Attraction ---
        // Smoothly move food toward the active magnet target instead of jumping by whole cells.
        for (int i = 0; i < foods.Count; i++) {
            bool playerActive = playerMagnetTicks > 0;
            bool enemyActive = enemyMagnetTicks > 0;
            PointF target;
            if (playerActive && enemyActive)
                target = (Distance(foods[i].Position, playerSnake[0]) <= Distance(foods[i].Position, enemySnake[0])) ? playerSnake[0] : enemySnake[0];
            else if (playerActive)
                target = playerSnake[0];
            else
                target = enemySnake[0];
            
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
        if (enemyMagnetTicks > 0) enemyMagnetTicks--;
        if (superFoodTicks > 0) superFoodTicks--;
        
        // --- Weak Magnetism from snake heads ---
        for (int i = 0; i < foods.Count; i++) {
            float vx = 0, vy = 0;
            if (Distance(foods[i].Position, playerSnake[0]) <= 1.0f) {
                float dx = playerSnake[0].X - foods[i].Position.X;
                float dy = playerSnake[0].Y - foods[i].Position.Y;
                float len = (float)Math.Sqrt(dx * dx + dy * dy);
                if (len > 0) { vx += 0.2f * dx / len; vy += 0.2f * dy / len; }
            }
            if (Distance(foods[i].Position, enemySnake[0]) <= 1.0f) {
                float dx = enemySnake[0].X - foods[i].Position.X;
                float dy = enemySnake[0].Y - foods[i].Position.Y;
                float len = (float)Math.Sqrt(dx * dx + dy * dy);
                if (len > 0) { vx += 0.2f * dx / len; vy += 0.2f * dy / len; }
            }
            Food f = foods[i];
            f.Position = new PointF(f.Position.X + vx, f.Position.Y + vy);
            foods[i] = f;
        }
        
        if (rand.NextDouble() < 0.05) GenerateFoods();
        lastUpdateTime = DateTime.Now;
    }
    
    bool IsOutOfBounds(PointF p) {
        return p.X < 0 || p.Y < 0 || p.X >= cols || p.Y >= rows;
    }
    
    void GenerateFoods() {
        double chance = rand.NextDouble();
        int count = chance < 0.025 ? 3 : (chance < 0.075 ? 2 : 1);
        for (int i = 0; i < count; i++) {
            Food newFood;
            do {
                newFood.Position = new PointF(rand.Next(0, cols), rand.Next(0, rows));
            } while (playerSnake.Any(p => Distance(p, newFood.Position) < 0.5f) ||
                     enemySnake.Any(p => Distance(p, newFood.Position) < 0.5f) ||
                     foods.Any(f => Distance(f.Position, newFood.Position) < 0.5f));
            double magneticChance = 0.065;
            double specialChance = 0.075;
            if (rand.NextDouble() < magneticChance) {
                newFood.IsMagnetic = true;
                newFood.IsSpecial = false;
                newFood.FoodColor = Color.Red;
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
        PointF p;
        do {
            p = new PointF(rand.Next(0, cols), rand.Next(0, rows));
        } while (playerSnake.Any(q => Distance(q, p) < 0.5f) || foods.Any(f => Distance(f.Position, p) < 0.5f));
        enemySnake.Add(p);
        enemyScore /= 2;
        enemyVX = 1f; enemyVY = 0f;
    }
    
    Color InterpolateColor(Color start, Color end, float t) {
        int r = (int)(start.R + (end.R - start.R) * t);
        int g = (int)(start.G + (end.G - start.G) * t);
        int b = (int)(start.B + (end.B - start.B) * t);
        return Color.FromArgb(r, g, b);
    }
    
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
        // Only trigger rainbow effect for player if super food is active.
        Color headColor = (isPlayer && superFoodTicks > 0) ? GetRainbowColor(rainbowPhase) : playerBaseColor;
        Color tailColor = (isPlayer && superFoodTicks > 0) ? GetRainbowColor(rainbowPhase + 0.3f) : ControlPaint.Dark(playerBaseColor);
        for (int i = 0; i < snake.Count; i++) {
            float t = snake.Count > 1 ? (float)i / (snake.Count - 1) : 0f;
            float radius = headRadius * (1 - t) + tailRadius * t;
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
        
        // Draw grid background over game area with gray lines and border.
        Rectangle gridRect = new Rectangle(0, 0, cols * cellSize, rows * cellSize);
        for (int i = 0; i <= cols; i++) {
            int x = i * cellSize;
            g.DrawLine(Pens.Gray, x, 0, x, gridRect.Height);
        }
        for (int j = 0; j <= rows; j++) {
            int y = j * cellSize;
            g.DrawLine(Pens.Gray, 0, y, gridRect.Width, y);
        }
        g.DrawRectangle(Pens.Gray, gridRect);
        
        float alpha = (float)(DateTime.Now - lastUpdateTime).TotalMilliseconds / logicTimer.Interval;
        if (alpha > 1f) alpha = 1f;
        
        DrawSnakeInterpolated(g, prevPlayerSnake, playerSnake, playerBaseColor, true, alpha);
        DrawSnakeInterpolated(g, prevEnemySnake, enemySnake, Color.Blue, false, alpha);
        
        foreach (var food in foods) {
            PointF prevPos = prevFoodPositions.ContainsKey(food.Id) ? prevFoodPositions[food.Id] : food.Position;
            PointF interpolated = Lerp(prevPos, food.Position, alpha);
            
            float cx = interpolated.X * cellSize + cellSize / 2f;
            float cy = interpolated.Y * cellSize + cellSize / 2f;
            
            if (food.IsMagnetic) {
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
        
        string scoreText = string.Format("Player: {0}    Enemy: {1}", playerScore, enemyScore);
        g.DrawString(scoreText, this.Font, Brushes.Black, 5, rows * cellSize + 5);
        if (enemySnake.Count > 0)
            g.DrawString("Enemy Pos: " + enemySnake[0], this.Font, Brushes.Blue, 5, rows * cellSize + 20);
    }
}

//
// Program: Start with the MainMenuForm.
//
public static class Program {
    [STAThread]
    public static void Main() {
        Application.EnableVisualStyles();
        Application.Run(new MainMenuForm());
    }
}
