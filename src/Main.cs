// This is Snek. Snek is an easter egg
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

public struct Move {
    public int dx;
    public int dy;
    public Move(int dx, int dy) {
        this.dx = dx;
        this.dy = dy;
    }
}

public class GameForm : Form {
    Timer timer;
    List<Point> playerSnake;
    List<Point> enemySnake;
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
    
    // New visual effect variables
    private float glowIntensity = 1.0f;
    private float rainbowPhase = 0f;
    private const float RAINBOW_SPEED = 0.05f;

    private struct Food {
        public Point Position;
        public bool IsSpecial;
        public Color FoodColor;
    }

    public GameForm() {
        this.ClientSize = new Size(cols * cellSize, rows * cellSize + 40);
        this.DoubleBuffered = true;
        this.Text = "Snek - Mouse or Arrow/WASD (keys override mouse)";
        this.KeyPreview = true;

        playerSnake = new List<Point> { new Point(cols / 2, rows / 2) };
        enemySnake = new List<Point> { new Point(cols / 4, rows / 4) };
        GenerateFoods();

        pendingDX = playerDX;
        pendingDY = playerDY;

        timer = new Timer { Interval = 100 };
        timer.Tick += (s, e) => UpdateGame();

        this.MouseClick += (s, e) => {
            if (!gameStarted && e.Button == MouseButtons.Left) {
                gameStarted = true;
                timer.Start();
            }
        };

        this.MouseMove += (s, e) => {
            if (!keyboardOverride)
                currentMousePosition = e.Location;
        };

        this.KeyDown += GameForm_KeyDown;
    }

    // New method to create glow effect
    private GraphicsPath CreateGlowPath(PointF center, float radius, float glowSize) {
        GraphicsPath path = new GraphicsPath();
        for (float size = radius; size <= radius + glowSize; size += glowSize / 4) {
            path.AddEllipse(center.X - size, center.Y - size, size * 2, size * 2);
        }
        return path;
    }

    // New method to generate rainbow colors
    private Color GetRainbowColor(float phase) {
        float frequency = 2.0f * (float)Math.PI;
        int r = (int)(Math.Sin(frequency * phase + 0) * 127 + 128);
        int g = (int)(Math.Sin(frequency * phase + 2) * 127 + 128);
        int b = (int)(Math.Sin(frequency * phase + 4) * 127 + 128);
        return Color.FromArgb(r, g, b);
    }

    // New method for drawing shiny eyes
    private void DrawShinyEye(Graphics g, PointF center, float eyeRadius, float pupilRadius) {
        RectangleF eyeRect = new RectangleF(
            center.X - eyeRadius, 
            center.Y - eyeRadius,
            eyeRadius * 2,
            eyeRadius * 2
        );
        
        // White of the eye
        g.FillEllipse(Brushes.White, eyeRect);
        
        // Add shine effect
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
            timer.Stop();
            //MessageBox.Show("Game Over! Your Score: " + playerScore);
            //Application.Exit();
            return;
        }
        playerSnake.Insert(0, newPlayerHead);
        int foodIndex = foods.FindIndex(f => newPlayerHead.Equals(f.Position));
        if (foodIndex != -1) {
            Food eaten = foods[foodIndex];
            if (eaten.IsSpecial) {
                playerScore += 30;
                playerBaseColor = eaten.FoodColor;
                Point tail = playerSnake[playerSnake.Count - 1];
                playerSnake.Add(tail);
                playerSnake.Add(tail);
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
        // Target the nearest food by Manhattan distance
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
            int enemyFoodIndex = foods.FindIndex(f => newEnemyHead.Equals(f.Position));
            if (enemyFoodIndex != -1) {
                Food eaten = foods[enemyFoodIndex];
                if (eaten.IsSpecial) {
                    enemyScore += 30;
                    Point tail = enemySnake[enemySnake.Count - 1];
                    enemySnake.Add(tail);
                    enemySnake.Add(tail);
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

        Invalidate();
    }

    bool IsOutOfBounds(Point p) {
        return p.X < 0 || p.Y < 0 || p.X >= cols || p.Y >= rows;
    }

    void GenerateFoods() {
        foods.Clear();
        double chance = rand.NextDouble();
        int count = chance < 0.25 ? 3 : (chance < 0.75 ? 2 : 1);
        for (int i = 0; i < count; i++) {
            Food newFood;
            do {
                newFood.Position = new Point(rand.Next(0, cols), rand.Next(0, rows));
            } while (playerSnake.Contains(newFood.Position) ||
                     enemySnake.Contains(newFood.Position) ||
                     foods.Any(f => f.Position == newFood.Position));
            newFood.IsSpecial = rand.NextDouble() < 0.2;
            newFood.FoodColor = newFood.IsSpecial 
                ? Color.FromArgb(rand.Next(256), rand.Next(256), rand.Next(256))
                : Color.Red;
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

    void DrawSnake(Graphics g, List<Point> snake, Color baseColor, bool isPlayer) {
        if (snake == null || snake.Count == 0)
            return;

        float headRadius = cellSize * 0.8f;
        float tailRadius = cellSize * 0.4f;
        
        // Create a rainbow effect for the player's snake
        Color headColor = isPlayer ? GetRainbowColor(rainbowPhase) : baseColor;
        Color tailColor = isPlayer ? GetRainbowColor(rainbowPhase + 0.3f) : ControlPaint.Dark(baseColor);

        for (int i = 0; i < snake.Count; i++) {
            float t = snake.Count > 1 ? (float)i / (snake.Count - 1) : 0f;
            float radius = headRadius * (1 - t) + tailRadius * t;
            Color nodeColor = InterpolateColor(headColor, tailColor, t);
            float cx = snake[i].X * cellSize + cellSize / 2f;
            float cy = snake[i].Y * cellSize + cellSize / 2f;
            
            // Add glow effect
            if (isPlayer) {
                using (GraphicsPath glowPath = CreateGlowPath(new PointF(cx, cy), radius, radius * 1.5f))
                using (PathGradientBrush glowBrush = new PathGradientBrush(glowPath)) {
                    Color glowColor = Color.FromArgb(
                        (int)(100 * glowIntensity),
                        nodeColor.R,
                        nodeColor.G,
                        nodeColor.B
                    );
                    glowBrush.CenterColor = glowColor;
                    glowBrush.SurroundColors = new Color[] { Color.FromArgb(0, nodeColor) };
                    g.FillPath(glowBrush, glowPath);
                }
            }

            RectangleF nodeRect = new RectangleF(cx - radius, cy - radius, radius * 2, radius * 2);
            
            // Add inner glow/shine
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

            // Enhanced player head decorations
            if (i == 0 && isPlayer) {
                // Add shiny effect to eyes
                float eyeRadius = radius * 0.3f;
                float pupilRadius = eyeRadius * 0.5f;
                PointF leftEyeCenter = new PointF(cx - radius * 0.4f, cy - radius * 0.4f);
                PointF rightEyeCenter = new PointF(cx + radius * 0.4f, cy - radius * 0.4f);
                
                // Draw eyes with shine
                DrawShinyEye(g, leftEyeCenter, eyeRadius, pupilRadius);
                DrawShinyEye(g, rightEyeCenter, eyeRadius, pupilRadius);

                // Enhanced hat with gradient
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

            // Draw smooth connecting capsules between segments
            if (i < snake.Count - 1) {
                float tNext = (float)(i + 1) / (snake.Count - 1);
                float nextRadius = headRadius * (1 - tNext) + tailRadius * tNext;
                Color nextColor = InterpolateColor(headColor, tailColor, tNext);
                PointF p1 = new PointF(cx, cy);
                PointF p2 = new PointF(snake[i + 1].X * cellSize + cellSize / 2f,
                                       snake[i + 1].Y * cellSize + cellSize / 2f);
                float dx = p2.X - p1.X;
                float dy = p2.Y - p1.Y;
                float angle = (float)Math.Atan2(dy, dx);
                PointF offset1 = new PointF(radius * (float)Math.Sin(angle), -radius * (float)Math.Cos(angle));
                PointF offset2 = new PointF(nextRadius * (float)Math.Sin(angle), -nextRadius * (float)Math.Cos(angle));

                using (GraphicsPath path = new GraphicsPath()) {
                    PointF p1a = new PointF(p1.X - offset1.X, p1.Y - offset1.Y);
                    PointF p2a = new PointF(p2.X - offset2.X, p2.Y - offset2.Y);
                    PointF p2b = new PointF(p2.X + offset2.X, p2.Y + offset2.Y);
                    PointF p1b = new PointF(p1.X + offset1.X, p1.Y + offset1.Y);
                    PointF[] capsulePts = new PointF[] { p1a, p2a, p2b, p1b };
                    path.AddPolygon(capsulePts);
                    if (Math.Abs(dx) < 0.001f && Math.Abs(dy) < 0.001f) {
                        using (SolidBrush solidBrush = new SolidBrush(nodeColor))
                            g.FillPath(solidBrush, path);
                    } else {
                        using (LinearGradientBrush lgBrush = new LinearGradientBrush(p1, p2, nodeColor, nextColor))
                            g.FillPath(lgBrush, path);
                    }
                }
            }
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        using (var bgBrush = new LinearGradientBrush(ClientRectangle, Color.LightGray, Color.DarkGray, 90F))
            e.Graphics.FillRectangle(bgBrush, ClientRectangle);
        base.OnPaint(e);
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        DrawSnake(g, playerSnake, playerBaseColor, true);
        DrawSnake(g, enemySnake, Color.Blue, false);

        foreach (var food in foods) {
            Rectangle foodRect = new Rectangle(food.Position.X * cellSize, food.Position.Y * cellSize, cellSize, cellSize);
            using (SolidBrush brush = new SolidBrush(food.FoodColor))
                g.FillEllipse(brush, foodRect);
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

