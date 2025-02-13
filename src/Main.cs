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
    Point food;
    int cellSize = 10, cols = 40, rows = 40;
    int playerDX = 1, playerDY = 0;
    int enemyDX = 1, enemyDY = 0;
    int playerScore = 0, enemyScore = 0;
    Random rand = new Random();
    float animationPhase = 0f; // drives the animated shading

    // Fields to handle mouse start and movement.
    bool gameStarted = false;
    Point currentMousePosition;

    public GameForm() {
        this.ClientSize = new Size(cols * cellSize, rows * cellSize + 40);
        this.DoubleBuffered = true;
        this.Text = "Snek - Mouse click to start";

        playerSnake = new List<Point> { new Point(cols / 2, rows / 2) };
        enemySnake = new List<Point> { new Point(cols / 4, rows / 4) };
        GenerateFood();

        timer = new Timer { Interval = 100 };
        timer.Tick += (s, e) => UpdateGame();
        // Start the game on left mouse click.
        this.MouseClick += (s, e) => {
            if (!gameStarted && e.Button == MouseButtons.Left) {
                gameStarted = true;
                timer.Start();
            }
        };

        this.MouseMove += (s, e) => {
            currentMousePosition = e.Location;
        };
    }

    void UpdateGame() {
        // Update animated shading.
        animationPhase += 0.2f;
        if (animationPhase > Math.PI * 2)
            animationPhase -= (float)(Math.PI * 2);

        // Compute candidate direction for the player's snake based on mouse.
        int mouseCellX = currentMousePosition.X / cellSize;
        int mouseCellY = currentMousePosition.Y / cellSize;
        int diffX = mouseCellX - playerSnake[0].X;
        int diffY = mouseCellY - playerSnake[0].Y;
        
        // Compute the angle from the head to the mouse.
        double inputAngle = Math.Atan2(diffY, diffX);
        double currentAngle = Math.Atan2(playerDY, playerDX);
        // Compute smallest angle difference.
        double delta = Math.Abs((inputAngle - currentAngle + Math.PI) % (2 * Math.PI) - Math.PI);
        
        int candidateDX = playerDX;
        int candidateDY = playerDY;
        // If nearly 180 degrees (reverse) then reject input.
        if (Math.Abs(delta - Math.PI) < 0.1) {
            candidateDX = playerDX;
            candidateDY = playerDY;
        } else {
            // Choose new direction based on dominant axis.
            if (Math.Abs(diffX) > Math.Abs(diffY)) {
                candidateDX = diffX > 0 ? 1 : -1;
                candidateDY = 0;
            } else if (diffY != 0) {
                candidateDY = diffY > 0 ? 1 : -1;
                candidateDX = 0;
            }
        }

        // Prevent player's snake from reversing into itself.
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

        // Update player's snake.
        Point playerHead = playerSnake[0];
        Point newPlayerHead = new Point(playerHead.X + playerDX, playerHead.Y + playerDY);
        bool playerGrowing = newPlayerHead.Equals(food);
        // Exclude tail if not growing.
        IEnumerable<Point> playerBody = (!playerGrowing && playerSnake.Count > 1) ?
            playerSnake.Skip(1).Take(playerSnake.Count - 1) : playerSnake.Skip(1);

        if (IsOutOfBounds(newPlayerHead) ||
            playerBody.Contains(newPlayerHead) ||
            enemySnake.Skip(1).Contains(newPlayerHead)) {
            timer.Stop();
            MessageBox.Show("Game Over! Your Score: " + playerScore);
            Application.Exit();
            return;
        }
        playerSnake.Insert(0, newPlayerHead);
        if (playerGrowing) {
            playerScore += 10;
            GenerateFood();
        } else {
            playerSnake.RemoveAt(playerSnake.Count - 1);
        }

        // Enemy snake AI with body avoidance.
        Point enemyHead = enemySnake[0];
        int enemyDiffX = food.X - enemyHead.X;
        int enemyDiffY = food.Y - enemyHead.Y;
        int candidateEnemyDX = Math.Abs(enemyDiffX) > Math.Abs(enemyDiffY) ? (enemyDiffX > 0 ? 1 : -1) : 0;
        int candidateEnemyDY = candidateEnemyDX == 0 ? (enemyDiffY > 0 ? 1 : -1) : 0;

        // Prevent enemy from reversing.
        if (enemySnake.Count > 1) {
            int currentEnemyDX = enemyHead.X - enemySnake[1].X;
            int currentEnemyDY = enemyHead.Y - enemySnake[1].Y;
            if (candidateEnemyDX == -currentEnemyDX && candidateEnemyDY == -currentEnemyDY) {
                candidateEnemyDX = currentEnemyDX;
                candidateEnemyDY = currentEnemyDY;
            }
        }

        // Check candidate move for self-collision.
        Point candidateEnemyHead = new Point(enemyHead.X + candidateEnemyDX, enemyHead.Y + candidateEnemyDY);
        bool candidateGrowing = candidateEnemyHead.Equals(food);
        var enemyBodyToCheck = (!candidateGrowing && enemySnake.Count > 1)
            ? enemySnake.Skip(1).Take(enemySnake.Count - 1)
            : enemySnake.Skip(1);
        bool safe = !IsOutOfBounds(candidateEnemyHead) && !enemyBodyToCheck.Contains(candidateEnemyHead);

        if (!safe) {
            // Try alternative moves (excluding reversal).
            var moves = new List<Move> { new Move(1, 0), new Move(-1, 0), new Move(0, 1), new Move(0, -1) };
            if (enemySnake.Count > 1) {
                int currentEnemyDX = enemyHead.X - enemySnake[1].X;
                int currentEnemyDY = enemyHead.Y - enemySnake[1].Y;
                moves.RemoveAll(m => m.dx == -currentEnemyDX && m.dy == -currentEnemyDY);
            }
            // Order moves by Manhattan distance to food.
            foreach (var move in moves.OrderBy(m => Math.Abs((enemyHead.X + m.dx) - food.X) + Math.Abs((enemyHead.Y + m.dy) - food.Y))) {
                Point newHead = new Point(enemyHead.X + move.dx, enemyHead.Y + move.dy);
                bool growing = newHead.Equals(food);
                var checkBody = (!growing && enemySnake.Count > 1)
                    ? enemySnake.Skip(1).Take(enemySnake.Count - 1)
                    : enemySnake.Skip(1);
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
        bool enemyGrowing = newEnemyHead.Equals(food);
        IEnumerable<Point> enemyBody = (!enemyGrowing && enemySnake.Count > 1) ?
            enemySnake.Skip(1).Take(enemySnake.Count - 1) : enemySnake.Skip(1);

        if (IsOutOfBounds(newEnemyHead) ||
            enemyBody.Contains(newEnemyHead) ||
            playerSnake.Skip(1).Contains(newEnemyHead)) {
            RespawnEnemy();
        } else {
            enemySnake.Insert(0, newEnemyHead);
            if (enemyGrowing) {
                enemyScore += 10;
                GenerateFood();
            } else {
                enemySnake.RemoveAt(enemySnake.Count - 1);
            }
        }

        Invalidate();
    }

    bool IsOutOfBounds(Point p) {
        return p.X < 0 || p.Y < 0 || p.X >= cols || p.Y >= rows;
    }

    void GenerateFood() {
        Point p;
        do {
            p = new Point(rand.Next(0, cols), rand.Next(0, rows));
        } while (playerSnake.Contains(p) || enemySnake.Contains(p));
        food = p;
    }

    void RespawnEnemy() {
        enemySnake.Clear();
        Point p;
        do {
            p = new Point(rand.Next(0, cols), rand.Next(0, rows));
        } while (playerSnake.Contains(p) || p.Equals(food));
        enemySnake.Add(p);
        enemyDX = 1;
        enemyDY = 0;
    }

    protected override void OnPaint(PaintEventArgs e) {
        using (var bgBrush = new LinearGradientBrush(ClientRectangle, Color.LightGray, Color.DarkGray, 90F))
            e.Graphics.FillRectangle(bgBrush, ClientRectangle);
        base.OnPaint(e);
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        // Draw player's snake with a green gradient.
        DrawSnake(g, playerSnake, Color.Green);
        // Draw enemy snake with a blue gradient.
        DrawSnake(g, enemySnake, Color.Blue);

        // Draw food.
        Rectangle foodRect = new Rectangle(food.X * cellSize, food.Y * cellSize, cellSize, cellSize);
        g.FillEllipse(Brushes.Red, foodRect);

        // Draw scores.
        string scoreText = string.Format("Player: {0}    Enemy: {1}", playerScore, enemyScore);
        g.DrawString(scoreText, this.Font, Brushes.Black, 5, rows * cellSize + 5);
        if (enemySnake.Count > 0)
            g.DrawString("Enemy Pos: " + enemySnake[0], this.Font, Brushes.Blue, 5, rows * cellSize + 20);
    }

    // Helper: Linear interpolation between two colors.
    Color InterpolateColor(Color start, Color end, float t) {
        int r = (int)(start.R + (end.R - start.R) * t);
        int g = (int)(start.G + (end.G - start.G) * t);
        int b = (int)(start.B + (end.B - start.B) * t);
        return Color.FromArgb(r, g, b);
    }

    void DrawSnake(Graphics g, List<Point> snake, Color baseColor) {
        if (snake == null || snake.Count == 0)
            return;

        // Define the head and tail properties.
        float headRadius = cellSize * 0.8f;
        float tailRadius = cellSize * 0.4f;
        // Use the base color at the head and a darker version at the tail.
        Color headColor = baseColor;
        Color tailColor = ControlPaint.Dark(baseColor);

        // Loop through each segment, drawing nodes and smooth connecting capsules.
        for (int i = 0; i < snake.Count; i++) {
            float t = snake.Count > 1 ? (float)i / (snake.Count - 1) : 0f;
            float radius = headRadius * (1 - t) + tailRadius * t;
            Color nodeColor = InterpolateColor(headColor, tailColor, t);
            float cx = snake[i].X * cellSize + cellSize / 2f;
            float cy = snake[i].Y * cellSize + cellSize / 2f;
            RectangleF nodeRect = new RectangleF(cx - radius, cy - radius, radius * 2, radius * 2);
            using (SolidBrush brush = new SolidBrush(nodeColor))
                g.FillEllipse(brush, nodeRect);
            using (Pen pen = new Pen(Color.Black, 1))
                g.DrawEllipse(pen, nodeRect);

            // If this is the player's snake head, add googley eyes and a party hat.
            if (i == 0 && baseColor == Color.Green) {
                // Draw googley eyes.
                float eyeRadius = radius * 0.3f;
                float pupilRadius = eyeRadius * 0.5f;
                // Position the eyes slightly above center.
                PointF leftEyeCenter = new PointF(cx - radius * 0.4f, cy - radius * 0.4f);
                PointF rightEyeCenter = new PointF(cx + radius * 0.4f, cy - radius * 0.4f);
                RectangleF leftEyeRect = new RectangleF(leftEyeCenter.X - eyeRadius, leftEyeCenter.Y - eyeRadius, eyeRadius * 2, eyeRadius * 2);
                RectangleF rightEyeRect = new RectangleF(rightEyeCenter.X - eyeRadius, rightEyeCenter.Y - eyeRadius, eyeRadius * 2, eyeRadius * 2);
                // White part of the eyes.
                g.FillEllipse(Brushes.White, leftEyeRect);
                g.FillEllipse(Brushes.White, rightEyeRect);
                // Pupils.
                RectangleF leftPupilRect = new RectangleF(leftEyeCenter.X - pupilRadius, leftEyeCenter.Y - pupilRadius, pupilRadius * 2, pupilRadius * 2);
                RectangleF rightPupilRect = new RectangleF(rightEyeCenter.X - pupilRadius, rightEyeCenter.Y - pupilRadius, pupilRadius * 2, pupilRadius * 2);
                g.FillEllipse(Brushes.Black, leftPupilRect);
                g.FillEllipse(Brushes.Black, rightPupilRect);

                // Draw party hat.
                PointF hatLeft = new PointF(cx - radius * 0.6f, cy - radius);
                PointF hatRight = new PointF(cx + radius * 0.6f, cy - radius);
                PointF hatTop = new PointF(cx, cy - radius - radius * 1.5f);
                PointF[] hatPoints = { hatLeft, hatTop, hatRight };
                g.FillPolygon(Brushes.Magenta, hatPoints);
                g.DrawPolygon(Pens.Black, hatPoints);
            }

            // For a smooth connection, fill a capsule between this node and the next.
            if (i < snake.Count - 1) {
                float tNext = (float)(i + 1) / (snake.Count - 1);
                float nextRadius = headRadius * (1 - tNext) + tailRadius * tNext;
                Color nextColor = InterpolateColor(headColor, tailColor, tNext);
                PointF p1 = new PointF(cx, cy);
                PointF p2 = new PointF(snake[i + 1].X * cellSize + cellSize / 2f,
                                       snake[i + 1].Y * cellSize + cellSize / 2f);
                // Calculate the perpendicular offset based on each circle's radius.
                float dx = p2.X - p1.X;
                float dy = p2.Y - p1.Y;
                float angle = (float)Math.Atan2(dy, dx);
                PointF offset1 = new PointF(radius * (float)Math.Sin(angle), -radius * (float)Math.Cos(angle));
                PointF offset2 = new PointF(nextRadius * (float)Math.Sin(angle), -nextRadius * (float)Math.Cos(angle));
                
                using (GraphicsPath path = new GraphicsPath()) {
                    PointF[] capsulePts = new PointF[] {
                        new PointF(p1.X + offset1.X, p1.Y + offset1.Y),
                        new PointF(p2.X + offset2.X, p2.Y + offset2.Y),
                        new PointF(p2.X - offset2.X, p2.Y - offset2.Y),
                        new PointF(p1.X - offset1.X, p1.Y - offset1.Y)
                    };
                    path.AddPolygon(capsulePts);
                    // Use a linear gradient to blend between node colors.
                    using (LinearGradientBrush lgBrush = new LinearGradientBrush(p1, p2, nodeColor, nextColor)) {
                        g.FillPath(lgBrush, path);
                    }
                }
            }
        }
    }
}

public static class Program {
    [STAThread]
    public static void Main() {
        Application.EnableVisualStyles();
        Application.Run(new GameForm());
    }
}
