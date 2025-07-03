using System;
using System.Net;
using System.IO;
using System.Text;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Collections.Generic;
using System.Windows.Forms;

//
// LeaderboardService: Handles score submission and leaderboard retrieval.
//
public class LeaderboardService
{
    private static readonly string WebAppUrl = "https://script.google.com/macros/s/AKfycbxwmLIqa4sWv1Q7Y9f9s17BALS_dGv1wKt9TaP3s6FoM_kvQ4T0MJoxSrmnRdaS7E2nLQ/exec";

    public static bool SubmitScore(string username, int score)
    {
        try
        {
            string postData = "{\"name\":\"" + username + "\", \"score\":" + score + "}";

            byte[] dataBytes = Encoding.UTF8.GetBytes(postData);

            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(WebAppUrl + "?action=submit");
            request.Method = "POST";
            request.ContentType = "application/json";
            request.ContentLength = dataBytes.Length;

            using (Stream requestStream = request.GetRequestStream())
            {
                requestStream.Write(dataBytes, 0, dataBytes.Length);
            }

            using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
            {
                using (StreamReader reader = new StreamReader(response.GetResponseStream()))
                {
                    string result = reader.ReadToEnd();
                    return response.StatusCode == HttpStatusCode.OK && result.Contains("Success");
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("Error submitting score: " + ex.Message);
            return false;
        }
    }

    public static string GetLeaderboard()
    {
        try
        {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(WebAppUrl + "?action=leaderboard");
            request.Method = "GET";

            using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
            {
                using (StreamReader reader = new StreamReader(response.GetResponseStream()))
                {
                    string result = reader.ReadToEnd();
                    return result;
                }
            }
        }
        catch (Exception ex)
        {
            return "Error fetching leaderboard: " + ex.Message;
        }
    }
}

//
// LeaderboardEntry: Represents a single leaderboard record.
//
public class LeaderboardEntry
{
    public string Username { get; set; }
    public int Score { get; set; }
    public DateTime Timestamp { get; set; }
}

//
// LeaderboardDisplayForm: Displays the leaderboard in a DataGridView.
// The ParseLeaderboardData method manually parses a JSON array of arrays.
// Expected format: [["DangerNoodle",40,"2025-03-08T07:18:41.488Z"],["DeezNoodles",20,"2025-03-08T07:19:28.400Z"]]
//
public class LeaderboardDisplayForm : Form
{
    public LeaderboardDisplayForm(string leaderboardData)
    {
        this.Text = "Leaderboard";
        this.ClientSize = new Size(400, 300);
        this.StartPosition = FormStartPosition.CenterScreen;
        this.FormBorderStyle = FormBorderStyle.FixedDialog;
        this.MaximizeBox = false;

        DataGridView grid = new DataGridView();
        grid.Dock = DockStyle.Fill;
        grid.ReadOnly = true;
        grid.AllowUserToAddRows = false;
        grid.AllowUserToDeleteRows = false;
        grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;

        List<LeaderboardEntry> entries = ParseLeaderboardData(leaderboardData);
        grid.DataSource = entries;
        this.Controls.Add(grid);

        Button closeButton = new Button();
        closeButton.Text = "Close";
        closeButton.Dock = DockStyle.Bottom;
        closeButton.Height = 30;
        closeButton.Click += new EventHandler((s, e) => { this.Close(); });
        this.Controls.Add(closeButton);
    }

    private List<LeaderboardEntry> ParseLeaderboardData(string json)
    {
        List<LeaderboardEntry> entries = new List<LeaderboardEntry>();
        json = json.Trim();
        if (json.StartsWith("[") && json.EndsWith("]"))
        {
            // Remove the outer brackets.
            json = json.Substring(1, json.Length - 2);
            // Split by "],[" since the inner arrays are separated by that.
            string[] parts = json.Split(new string[] { "],[" }, StringSplitOptions.None);
            foreach (var part in parts)
            {
                // Remove any stray brackets.
                string clean = part.Replace("[", "").Replace("]", "");
                // Now expect: "DangerNoodle",40,"2025-03-08T07:18:41.488Z"
                string[] items = clean.Split(',');
                if (items.Length >= 3)
                {
                    string username = items[0].Trim(' ', '"');
                    int score = int.Parse(items[1]);
                    DateTime timestamp = DateTime.Parse(items[2].Trim(' ', '"'));
                    entries.Add(new LeaderboardEntry { Username = username, Score = score, Timestamp = timestamp });
                }
            }
        }
        return entries;
    }
}

//
// UsernamePromptForm: Prompts the player for their username.
//
public class UsernamePromptForm : Form
{
    private TextBox usernameTextBox;
    private Button okButton;
    private Button cancelButton;
    private Label promptLabel;

    public string Username
    {
        get { return usernameTextBox.Text; }
    }

    public UsernamePromptForm()
    {
        this.Text = "Enter Username";
        this.ClientSize = new Size(300, 120);
        this.FormBorderStyle = FormBorderStyle.FixedDialog;
        this.StartPosition = FormStartPosition.CenterScreen;
        this.MaximizeBox = false;
        this.MinimizeBox = false;

        promptLabel = new Label();
        promptLabel.Text = "Please enter your username:";
        promptLabel.Location = new Point(10, 10);
        promptLabel.Size = new Size(280, 20);
        this.Controls.Add(promptLabel);

        usernameTextBox = new TextBox();
        usernameTextBox.Location = new Point(10, 35);
        usernameTextBox.Size = new Size(280, 20);
        this.Controls.Add(usernameTextBox);

        okButton = new Button();
        okButton.Text = "OK";
        okButton.Location = new Point(135, 70);
        okButton.Click += new EventHandler(okButton_Click);
        this.Controls.Add(okButton);

        cancelButton = new Button();
        cancelButton.Text = "Cancel";
        cancelButton.Location = new Point(215, 70);
        cancelButton.Click += new EventHandler(cancelButton_Click);
        this.Controls.Add(cancelButton);
    }

    private void okButton_Click(object sender, EventArgs e)
    {
        if (usernameTextBox.Text.Trim() == "")
        {
            MessageBox.Show("Username cannot be empty.");
            return;
        }
        this.DialogResult = DialogResult.OK;
        this.Close();
    }

    private void cancelButton_Click(object sender, EventArgs e)
    {
        this.DialogResult = DialogResult.Cancel;
        this.Close();
    }
}

//
// MainMenuForm: The startup screen with instructions, changelog, and start button.
//
public class MainMenuForm : Form
{
    private DataGridView leaderboardGrid;

    public MainMenuForm()
    {
        this.Text = "Snek Menu - Version 1.1.17";
        this.ClientSize = new Size(600, 500);
        this.StartPosition = FormStartPosition.CenterScreen;
        this.FormBorderStyle = FormBorderStyle.FixedSingle;
        this.MaximizeBox = false;

        // Existing instructions and changelog controls.
        Label instructionsLabel = new Label();
        instructionsLabel.Text = "Controls:\n- Move snake with mouse (WASD/Arrow keys override).\n- Press Space or hold mouse down to boost (costs 1 segment/tick).\n- Magnetic and special food trigger unique effects.\n- Escape to pause";
        instructionsLabel.Location = new Point(20, 20);
        instructionsLabel.Size = new Size(280, 150);
        instructionsLabel.Font = new Font("Arial", 10);
        instructionsLabel.AutoSize = false;

        GroupBox changelogBox = new GroupBox();
        changelogBox.Text = "Changelog";
        changelogBox.Location = new Point(320, 20);
        changelogBox.Size = new Size(250, 300);
        Label changelogLabel = new Label();
        changelogLabel.Text = "Version 1.1.17:\n- Removed API hit from initialization logic\n- Improved startup times";
        changelogLabel.Location = new Point(10, 20);
        changelogLabel.Size = new Size(230, 270);
        changelogLabel.Font = new Font("Arial", 9);
        changelogLabel.AutoSize = false;
        changelogLabel.TextAlign = ContentAlignment.TopLeft;
        changelogBox.Controls.Add(changelogLabel);

        Button startButton = new Button();
        startButton.Text = "Start Game";
        startButton.Location = new Point(350, 430);
        startButton.Size = new Size(100, 40);
        startButton.Click += new EventHandler((s, e) => {
            GameForm gameForm = new GameForm();
            gameForm.StartPosition = FormStartPosition.CenterScreen;
            gameForm.Show();
            this.Hide();
        });

        // GroupBox for the leaderboard.
        GroupBox leaderboardBox = new GroupBox();
        leaderboardBox.Text = "Leaderboard";
        leaderboardBox.Location = new Point(20, 270);
        leaderboardBox.Size = new Size(280, 180);

        leaderboardGrid = new DataGridView();
        leaderboardGrid.Dock = DockStyle.Fill;
        leaderboardGrid.ReadOnly = true;
        leaderboardGrid.AllowUserToAddRows = false;
        leaderboardGrid.AllowUserToDeleteRows = false;
        leaderboardGrid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        leaderboardBox.Controls.Add(leaderboardGrid);

        // Start with an empty leaderboard to reduce startup delay.
        leaderboardGrid.DataSource = new List<LeaderboardEntry>();

        // Button to load the leaderboard on demand.
        Button loadLeaderboardButton = new Button();
        loadLeaderboardButton.Text = "Load Leaderboard";
        loadLeaderboardButton.Location = new Point(20, 460);
        loadLeaderboardButton.Size = new Size(120, 30);
        loadLeaderboardButton.Click += new EventHandler(LoadLeaderboardButton_Click);

        // Add all controls.
        this.Controls.Add(instructionsLabel);
        this.Controls.Add(changelogBox);
        this.Controls.Add(leaderboardBox);
        this.Controls.Add(startButton);
        this.Controls.Add(loadLeaderboardButton);
    }

    private void LoadLeaderboardButton_Click(object sender, EventArgs e)
    {
        string leaderboardData = LeaderboardService.GetLeaderboard();
        List<LeaderboardEntry> entries = ParseLeaderboardData(leaderboardData);
        leaderboardGrid.DataSource = entries;
    }

    // Manual JSON parsing logic.
    private List<LeaderboardEntry> ParseLeaderboardData(string json)
    {
        List<LeaderboardEntry> entries = new List<LeaderboardEntry>();
        json = json.Trim();
        if (json.StartsWith("[") && json.EndsWith("]"))
        {
            // Remove the outer brackets.
            json = json.Substring(1, json.Length - 2);
            // Split by "],["
            string[] parts = json.Split(new string[] { "],[" }, StringSplitOptions.None);
            foreach (string part in parts)
            {
                string clean = part.Replace("[", "").Replace("]", "");
                // Expecting: "username",score,"timestamp"
                string[] items = clean.Split(',');
                if (items.Length >= 3)
                {
                    string username = items[0].Trim(' ', '"');
                    int score = int.Parse(items[1]);
                    DateTime timestamp = DateTime.Parse(items[2].Trim(' ', '"'));
                    entries.Add(new LeaderboardEntry() { Username = username, Score = score, Timestamp = timestamp });
                }
            }
        }
        return entries;
    }
}



//
// GameForm: The main game with circular boundary, camera tracking, multiple enemy snakes, and a rolling death log overlay.
//
public class GameForm : Form
{
    Timer logicTimer;
    Timer renderTimer;
    List<PointF> playerSnake;
    List<PointF> prevPlayerSnake;
    List<EnemySnake> enemySnakes;
    Dictionary<int, PointF> prevFoodPositions = new Dictionary<int, PointF>();
    List<Food> foods = new List<Food>();
    int cellSize = 10, cols = 40, rows = 40;
    PointF mapCenter;
    float mapRadius;
    float playerVX = 1f, playerVY = 0f;
    int playerScore = 0;
    Random rand = new Random();
    float animationPhase = 0f;
    Color playerBaseColor = Color.Green;
    bool gameStarted = false;
    bool keyboardOverride = false;
    Point currentMousePosition;
    bool isBoosting = false;
    float baseSpeed = 1.0f;
    float glowIntensity = 1.0f;
    float rainbowPhase = 0f;
    const float RAINBOW_SPEED = 0.05f;
    DateTime lastUpdateTime;
    int playerMagnetTicks = 0;
    int superFoodTicks = 0;
    int bigHeadTicks = 0;
    const float collisionThreshold = 0.7f;
    private bool deathLogEnabled = true;
    private List<string> deathLog = new List<string>();

    // Added: pause/resume
    bool isPaused = false;  

    private struct Food
    {
        public int Id;
        public PointF Position;
        public bool IsSpecial;
        public bool IsMagnetic;
        public bool IsBigHead;
        public Color FoodColor;
    }
    int nextFoodId = 0;

    private class EnemySnake
    {
        public List<PointF> Segments;
        public List<PointF> PrevSegments;
        public float VX, VY;
        public Color BaseColor;
        public string Name;
        public int MagnetTicks;
        public int Score;

        public EnemySnake(PointF spawn, Color baseColor, string name)
        {
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

    public GameForm()
    {
        this.ClientSize = new Size(cols * cellSize, rows * cellSize + 40);
        this.DoubleBuffered = true;
        this.Text = "Snek - Version 1.1.6";
        this.KeyPreview = true;
        mapCenter = new PointF(cols / 2f, rows / 2f);
        mapRadius = Math.Max(cols, rows) * 1.5f;
        playerSnake = new List<PointF> { new PointF(cols / 2f, rows / 2f) };
        prevPlayerSnake = playerSnake.Select(p => new PointF(p.X, p.Y)).ToList();
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
            if (!gameStarted && e.Button == MouseButtons.Left)
            {
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

    private void AddDeathLog(string message)
    {
        if (!deathLogEnabled) return;
        if (deathLog.Count >= 5)
            deathLog.RemoveAt(0);
        deathLog.Add(message);
    }

    private PointF Lerp(PointF a, PointF b, float t)
    {
        return new PointF(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t);
    }

    private float Distance(PointF a, PointF b)
    {
        float dx = a.X - b.X, dy = a.Y - b.Y;
        return (float)Math.Sqrt(dx * dx + dy * dy);
    }

    private GraphicsPath CreateGlowPath(PointF center, float radius, float glowSize)
    {
        GraphicsPath path = new GraphicsPath();
        for (float size = radius; size <= radius + glowSize; size += glowSize / 4)
            path.AddEllipse(center.X - size, center.Y - size, size * 2, size * 2);
        return path;
    }

    private Color GetRainbowColor(float phase)
    {
        float frequency = 2.0f * (float)Math.PI;
        int r = (int)(Math.Sin(frequency * phase + 0) * 127 + 128);
        int g = (int)(Math.Sin(frequency * phase + 2) * 127 + 128);
        int b = (int)(Math.Sin(frequency * phase + 4) * 127 + 128);
        return Color.FromArgb(r, g, b);
    }

    private void DrawShinyEye(Graphics g, PointF center, float eyeRadius, float pupilRadius)
    {
        RectangleF eyeRect = new RectangleF(center.X - eyeRadius, center.Y - eyeRadius, eyeRadius * 2, eyeRadius * 2);
        g.FillEllipse(Brushes.White, eyeRect);
        using (PathGradientBrush shine = new PathGradientBrush(new PointF[] {
            new PointF(center.X - eyeRadius * 0.7f, center.Y - eyeRadius * 0.7f),
            new PointF(center.X + eyeRadius * 0.7f, center.Y - eyeRadius * 0.7f),
            new PointF(center.X, center.Y + eyeRadius * 0.7f)
        }))
        {
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
        }))
        {
            pupilBrush.CenterColor = Color.Black;
            pupilBrush.SurroundColors = new Color[] { Color.FromArgb(255, 40, 40, 40) };
            g.FillEllipse(pupilBrush, pupilRect);
        }
    }

    private void GameForm_KeyDown(object sender, KeyEventArgs e)
    {
        // Added to toggle pause on ESC
        if(e.KeyCode == Keys.Escape)
        {
            isPaused = !isPaused;
            if(isPaused)
            {
                logicTimer.Stop();
                renderTimer.Stop();
            }
            else
            {
                lastUpdateTime = DateTime.Now;
                logicTimer.Start();
                renderTimer.Start();
            }
            return;
        }

        keyboardOverride = true;
        if (e.KeyCode == Keys.Up || e.KeyCode == Keys.W)
        {
            playerVX = 0; playerVY = -1;
        }
        else if (e.KeyCode == Keys.Down || e.KeyCode == Keys.S)
        {
            playerVX = 0; playerVY = 1;
        }
        else if (e.KeyCode == Keys.Left || e.KeyCode == Keys.A)
        {
            playerVX = -1; playerVY = 0;
        }
        else if (e.KeyCode == Keys.Right || e.KeyCode == Keys.D)
        {
            playerVX = 1; playerVY = 0;
        }
        else if (e.KeyCode == Keys.Space)
        {
            isBoosting = true;
        }
    }

    bool IsOutOfBounds(PointF p)
    {
        return Distance(p, mapCenter) > mapRadius;
    }

    private PointF GenerateRandomPositionInMap()
    {
        double angle = rand.NextDouble() * 2 * Math.PI;
        double r = Math.Sqrt(rand.NextDouble()) * mapRadius;
        float x = (float)(mapCenter.X + r * Math.Cos(angle));
        float y = (float)(mapCenter.Y + r * Math.Sin(angle));
        return new PointF(x, y);
    }

    void UpdateGame()
    {
        if (isPaused) return;

        float pickupThreshold = 1.2f;
        prevPlayerSnake = playerSnake.Select(p => new PointF(p.X, p.Y)).ToList();
        foreach (var enemy in enemySnakes)
            enemy.PrevSegments = enemy.Segments.Select(p => new PointF(p.X, p.Y)).ToList();
        Dictionary<int, PointF> newPrevFoodPositions = new Dictionary<int, PointF>();
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
        if (!keyboardOverride)
        {
            float targetX = currentMousePosition.X / (float)cellSize + (head.X - (ClientSize.Width / (2f * cellSize)));
            float targetY = currentMousePosition.Y / (float)cellSize + (head.Y - (ClientSize.Height / (2f * cellSize)));
            float diffX = targetX - head.X;
            float diffY = targetY - head.Y;
            float len = (float)Math.Sqrt(diffX * diffX + diffY * diffY);
            if (len > 0.0001f)
            {
                candidateVX = diffX / len;
                candidateVY = diffY / len;
            }
            else
            {
                candidateVX = playerVX;
                candidateVY = playerVY;
            }
        }
        else
        {
            candidateVX = playerVX;
            candidateVY = playerVY;
        }
        playerVX = candidateVX;
        playerVY = candidateVY;
        float boostMult = (isBoosting && playerSnake.Count > 1) ? 1.5f : 1.0f;
        PointF newHead = new PointF(head.X + playerVX * baseSpeed * boostMult, head.Y + playerVY * baseSpeed * boostMult);

        if (IsOutOfBounds(newHead) ||
            enemySnakes.Any(enemy => enemy.Segments.Skip(1).Any(p => Distance(p, newHead) < collisionThreshold)))
        {
            if (deathLogEnabled)
            {
                if (IsOutOfBounds(newHead))
                    AddDeathLog("Player went out of bounds.");
                else
                {
                    EnemySnake killer = enemySnakes.First(e => e.Segments.Skip(1).Any(p => Distance(p, newHead) < collisionThreshold));
                    AddDeathLog(killer.Name + " killed Player.");
                }
            }

            logicTimer.Stop();
            renderTimer.Stop();
            MessageBox.Show("Game Over! Your Score: " + playerScore);
            ShowLeaderboard();
            return;
        }
        playerSnake.Insert(0, newHead);
        // --- Player eats food ---
        float range = pickupThreshold * ((bigHeadTicks > 0) ? 5 : 1);
        var eatenFoods = foods.Where(f => Distance(newHead, f.Position) < range).ToList();

        if (eatenFoods.Any())
        {
            int totalSegments = 0;
            foreach (var eaten in eatenFoods)
            {
                // score & segment logic
                if (eaten.IsMagnetic)
                {
                    playerScore += 20;
                    totalSegments += 3;
                    playerMagnetTicks = 20;
                }
                else if (eaten.IsBigHead)
                {
                    playerScore += 40;
                    totalSegments += 4;
                    bigHeadTicks = 150;
                }
                else if (eaten.IsSpecial)
                {
                    playerScore += 100;
                    totalSegments += 30;
                    superFoodTicks = 100;
                }
                else
                {
                    playerScore += 10;
                }
                foods.Remove(eaten);
            }
            // grow snake by all eaten segments
            PointF tail = playerSnake[playerSnake.Count - 1];
            for (int i = 0; i < totalSegments; i++)
                playerSnake.Add(tail);
        }
        else
        {
            // no food, advance as usual
            playerSnake.RemoveAt(playerSnake.Count - 1);
            if (isBoosting && playerSnake.Count > 1)
            {
                playerSnake.RemoveAt(playerSnake.Count - 1);
            }
        }

        // --- Enemy Update ---
        if (foods.Count == 0) GenerateFoods();

        foreach (var enemy in enemySnakes)
        {
            PointF enemyHead = enemy.Segments[0];
            if (!foods.Any())
            {
                GenerateFoods();
            }
            if (!foods.Any()) continue;

            Food targetFood = foods.OrderBy(f => Distance(f.Position, enemyHead)).First();
            float diffEx = targetFood.Position.X - enemyHead.X;
            float diffEy = targetFood.Position.Y - enemyHead.Y;
            float lenE = (float)Math.Sqrt(diffEx * diffEx + diffEy * diffEy);
            float desiredVX = (lenE > 0.0001f) ? diffEx / lenE : enemy.VX;
            float desiredVY = (lenE > 0.0001f) ? diffEy / lenE : enemy.VY;

            List<CandidateMove> candidates = new List<CandidateMove>();
            float baseAngle = (float)Math.Atan2(desiredVY, desiredVX);
            float[] angleOffsets = new float[] { 0, 15, -15, 30, -30, 45, -45 };
            foreach (var offset in angleOffsets)
            {
                float radOffset = offset * (float)Math.PI / 180f;
                float testAngle = baseAngle + radOffset;
                float testVX = (float)Math.Cos(testAngle);
                float testVY = (float)Math.Sin(testAngle);
                PointF testHead = new PointF(enemyHead.X + testVX * baseSpeed, enemyHead.Y + testVY * baseSpeed);
                if (IsEnemyMoveSafe(enemy, testHead))
                {
                    float minDistToPlayer = playerSnake.Min(p => Distance(p, testHead));
                    candidates.Add(new CandidateMove(testVX, testVY, minDistToPlayer));
                }
            }

            if (candidates.Count == 0)
            {
                AddDeathLog("Player killed " + enemy.Name + ".");
                RespawnEnemy(enemy);
                continue;
            }

            CandidateMove best = candidates.OrderByDescending(c => c.Dist).First();
            enemy.VX = best.VX;
            enemy.VY = best.VY;

            PointF newEnemyHead = new PointF(enemyHead.X + enemy.VX * baseSpeed, enemyHead.Y + enemy.VY * baseSpeed);
            if (!IsEnemyMoveSafe(enemy, newEnemyHead))
            {
                AddDeathLog("Player killed " + enemy.Name + ".");
                RespawnEnemy(enemy);
                continue;
            }
            enemy.Segments.Insert(0, newEnemyHead);

            int enemyFoodIndex = foods.FindIndex(f => Distance(newEnemyHead, f.Position) < 1.2f);
            if (enemyFoodIndex != -1)
            {
                Food eaten = foods[enemyFoodIndex];
                if (eaten.IsMagnetic)
                {
                    enemy.Score = enemy.Score + 20;
                    PointF tail = enemy.Segments[enemy.Segments.Count - 1];
                    for (int i = 0; i < 3; i++) enemy.Segments.Add(tail);
                    enemy.MagnetTicks = 20;
                }
                else if (eaten.IsBigHead)
                {
                    enemy.Score = enemy.Score + 40;
                    PointF tail = enemy.Segments[enemy.Segments.Count - 1];
                    for (int i = 0; i < 4; i++) enemy.Segments.Add(tail);
                }
                else if (eaten.IsSpecial)
                {
                    enemy.Score = enemy.Score + 100;
                    PointF tail = enemy.Segments[enemy.Segments.Count - 1];
                    for (int i = 0; i < 10; i++) enemy.Segments.Add(tail);
                }
                else
                {
                    enemy.Score = enemy.Score + 10;
                }
                foods.RemoveAt(enemyFoodIndex);
            }
            else
            {
                enemy.Segments.RemoveAt(enemy.Segments.Count - 1);
            }

            if (enemy.MagnetTicks > 0) enemy.MagnetTicks--;
        }

        // --- Magnetic Food Attraction ---
        for (int i = 0; i < foods.Count; i++)
        {
            bool playerActive = playerMagnetTicks > 0;
            bool enemyActive = enemySnakes.Any(e => e.MagnetTicks > 0);
            if (!playerActive && !enemyActive)
                continue;
            PointF target;
            if (playerActive && enemyActive)
            {
                float playerDist = Distance(foods[i].Position, playerSnake[0]);
                var activeEnemies = enemySnakes.Where(e => e.MagnetTicks > 0).ToList();
                float enemyDist = activeEnemies.Min(e => Distance(e.Segments[0], foods[i].Position));
                target = (playerDist <= enemyDist)
                    ? playerSnake[0]
                    : activeEnemies.First(e => Distance(e.Segments[0], foods[i].Position) == enemyDist).Segments[0];
            }
            else if (playerActive)
            {
                target = playerSnake[0];
            }
            else
            {
                target = enemySnakes.First(e => e.MagnetTicks > 0).Segments[0];
            }

            float attractionSpeed = 0.5f;
            float diffX = target.X - foods[i].Position.X;
            float diffY = target.Y - foods[i].Position.Y;
            float dist = (float)Math.Sqrt(diffX * diffX + diffY * diffY);
            if (dist > 0.0001f)
            {
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

    private bool IsEnemyMoveSafe(EnemySnake enemy, PointF newHead)
    {
        const float playerAvoidanceDistance = 1.0f;
        if (IsOutOfBounds(newHead))
            return false;
        if (playerSnake.Any(p => Distance(p, newHead) < playerAvoidanceDistance))
            return false;
        foreach (var other in enemySnakes)
        {
            if (other == enemy) continue;
            if (other.Segments.Any(p => Distance(p, newHead) < collisionThreshold))
                return false;
        }
        return true;
    }

    private void RespawnEnemy(EnemySnake enemy)
    {
        // 1. Drop all current segments as regular food of the enemy's color
        foreach (var segment in enemy.Segments)
        {
            Food dropped = new Food {
                Id        = nextFoodId++,
                Position  = segment,
                IsSpecial = false,
                IsMagnetic= false,
                IsBigHead = false,
                FoodColor = enemy.BaseColor
            };
            foods.Add(dropped);
        }

        // 2. Now clear and respawn
        enemy.Segments.Clear();
        PointF p;
        do
        {
            p = GenerateRandomPositionInMap();
        }
        while (playerSnake.Any(q => Distance(q, p) < 0.5f) ||
               foods.Any(f => Distance(f.Position, p) < 0.5f));
        enemy.Segments.Add(p);
        enemy.Score      /= 2;
        enemy.VX          = 1f;
        enemy.VY          = 0f;
        enemy.MagnetTicks = 0;
    }


    void GenerateFoods()
    {
        int count = 10;
        for (int i = 0; i < count; i++)
        {
            Food newFood;
            do
            {
                newFood.Position = GenerateRandomPositionInMap();
            }
            while (playerSnake.Any(p => Distance(p, newFood.Position) < 0.5f) ||
                   enemySnakes.Any(e => e.Segments.Any(p => Distance(p, newFood.Position) < 0.5f)) ||
                   foods.Any(f => Distance(f.Position, newFood.Position) < 0.5f));
            double bigHeadChance = 0.025;
            double magneticChance = 0.020;
            double specialChance = 0.085;
            if (rand.NextDouble() < bigHeadChance)
            {
                newFood.IsBigHead = true;
                newFood.IsSpecial = false;
                newFood.IsMagnetic = false;
                newFood.FoodColor = Color.Empty;
            }
            else if (rand.NextDouble() < magneticChance)
            {
                newFood.IsMagnetic = true;
                newFood.IsSpecial = false;
                newFood.IsBigHead = false;
                newFood.FoodColor = Color.Red;
            }
            else if (rand.NextDouble() < specialChance)
            {
                newFood.IsSpecial = true;
                newFood.IsMagnetic = false;
                newFood.IsBigHead = false;
                newFood.FoodColor = Color.Empty;
            }
            else
            {
                newFood.IsSpecial = false;
                newFood.IsMagnetic = false;
                newFood.IsBigHead = false;
                newFood.FoodColor = Color.FromArgb(191, rand.Next(256), rand.Next(256), rand.Next(256));
            }
            newFood.Id = nextFoodId++;
            foods.Add(newFood);
        }
    }

    Color InterpolateColor(Color start, Color end, float t)
    {
        int r = (int)(start.R + (end.R - start.R) * t);
        int g = (int)(start.G + (end.G - start.G) * t);
        int b = (int)(start.B + (end.B - start.B) * t);
        return Color.FromArgb(r, g, b);
    }

    private const int RenderSegmentCap = 125;


    void DrawSnakeInterpolated(Graphics g, List<PointF> prevSnake, List<PointF> snake, Color baseColor, bool isPlayer, float alpha)
    {
        if (snake == null || snake.Count == 0) return;

        int renderCount = Math.Min(snake.Count, RenderSegmentCap);

        // ultra-ultra-slow growth past the cap (10th-root)
        float lengthScale = snake.Count > RenderSegmentCap
            ? (float)Math.Pow((double)snake.Count / RenderSegmentCap, 0.1)
            : 1f;

        // build interpolated positions
        List<PointF> interp = new List<PointF>(renderCount);
        for (int i = 0; i < renderCount; i++)
        {
            PointF from = (i < prevSnake.Count) ? prevSnake[i] : snake[i];
            PointF to   = snake[i];
            interp.Add(Lerp(from, to, alpha));
        }

        // apply uniform scale
        float headRadius = cellSize * 0.8f * lengthScale;
        float tailRadius = cellSize * 0.4f * lengthScale;

        Color headColor = (isPlayer && superFoodTicks > 0)
            ? GetRainbowColor(rainbowPhase)
            : (isPlayer ? playerBaseColor : baseColor);
        Color tailColor = (isPlayer && superFoodTicks > 0)
            ? GetRainbowColor(rainbowPhase + 0.3f)
            : (isPlayer ? ControlPaint.Dark(playerBaseColor) : ControlPaint.Dark(baseColor));

        for (int i = 0; i < renderCount; i++)
        {
            float t = (snake.Count > 1) ? (float)i / (snake.Count - 1) : 0f;
            float radius = headRadius * (1 - t) + tailRadius * t;

            if (isPlayer && i == 0 && bigHeadTicks > 0)
            {
                float elapsed = 150 - bigHeadTicks;
                float tNorm = elapsed / 150f;
                radius *= 1 + 4 * (float)Math.Sin(Math.PI * tNorm);
            }

            Color nodeColor = InterpolateColor(headColor, tailColor, t);
            float cx = interp[i].X * cellSize + cellSize / 2f;
            float cy = interp[i].Y * cellSize + cellSize / 2f;

            // player glow
            if (isPlayer)
            {
                using (GraphicsPath glowPath = CreateGlowPath(new PointF(cx, cy), radius, radius * 1.5f))
                using (PathGradientBrush glowBrush = new PathGradientBrush(glowPath))
                {
                    Color glowColor = Color.FromArgb((int)(100 * glowIntensity), nodeColor);
                    glowBrush.CenterColor = glowColor;
                    glowBrush.SurroundColors = new[] { Color.FromArgb(0, nodeColor) };
                    g.FillPath(glowBrush, glowPath);
                }
            }

            // draw segment
            RectangleF nodeRect = new RectangleF(cx - radius, cy - radius, radius * 2, radius * 2);
            using (PathGradientBrush innerGlow = new PathGradientBrush(new[]
            {
                new PointF(cx - radius, cy - radius),
                new PointF(cx + radius, cy - radius),
                new PointF(cx + radius, cy + radius),
                new PointF(cx - radius, cy + radius)
            }))
            {
                innerGlow.CenterColor = Color.FromArgb(200, 255, 255, 255);
                innerGlow.SurroundColors = new[] { Color.FromArgb(0, 255, 255, 255) };
                g.FillEllipse(innerGlow, nodeRect);
            }
            using (SolidBrush brush = new SolidBrush(nodeColor))
                g.FillEllipse(brush, nodeRect);
            using (Pen pen = new Pen(Color.FromArgb(100, Color.White), 2))
                g.DrawEllipse(pen, nodeRect);

            // player eyes and hat
            if (isPlayer && i == 0)
            {
                float eyeR = radius * 0.3f;
                float pupilR = eyeR * 0.5f;
                DrawShinyEye(g, new PointF(cx - radius * 0.4f, cy - radius * 0.4f), eyeR, pupilR);
                DrawShinyEye(g, new PointF(cx + radius * 0.4f, cy - radius * 0.4f), eyeR, pupilR);

                var hatL = new PointF(cx - radius * 0.6f, cy - radius);
                var hatR = new PointF(cx + radius * 0.6f, cy - radius);
                var hatT = new PointF(cx, cy - radius - radius * 1.5f);
                using (var brush2 = new LinearGradientBrush(
                    Point.Round(hatL), Point.Round(hatR),
                    GetRainbowColor(rainbowPhase + 0.2f),
                    GetRainbowColor(rainbowPhase + 0.7f)))
                {
                    g.FillPolygon(brush2, new[] { hatL, hatT, hatR });
                    g.DrawPolygon(new Pen(Color.FromArgb(100, Color.White), 2), new[] { hatL, hatT, hatR });
                }
            }

            // connecting capsule
            if (i < renderCount - 1)
            {
                float tNext = (float)(i + 1) / (renderCount - 1);
                float nextR = headRadius * (1 - tNext) + tailRadius * tNext;
                Color nextColor = InterpolateColor(headColor, tailColor, tNext);

                var p1 = new PointF(cx, cy);
                var p2 = new PointF(interp[i + 1].X * cellSize + cellSize / 2f,
                                     interp[i + 1].Y * cellSize + cellSize / 2f);
                float dx = p2.X - p1.X, dy = p2.Y - p1.Y;
                float angle = (float)Math.Atan2(dy, dx);

                var off1 = new PointF(radius * (float)Math.Sin(angle), -radius * (float)Math.Cos(angle));
                var off2 = new PointF(nextR * (float)Math.Sin(angle), -nextR * (float)Math.Cos(angle));
                using (var path = new GraphicsPath())
                {
                    path.AddPolygon(new[]
                    {
                        new PointF(p1.X - off1.X, p1.Y - off1.Y),
                        new PointF(p2.X - off2.X, p2.Y - off2.Y),
                        new PointF(p2.X + off2.X, p2.Y + off2.Y),
                        new PointF(p1.X + off1.X, p1.Y + off1.Y)
                    });
                    g.FillPath(
                        new SolidBrush((Math.Abs(dx) < 0.001f && Math.Abs(dy) < 0.001f)
                            ? nodeColor
                            : InterpolateColor(nodeColor, nextColor, 0.5f)),
                        path);
                }
            }
        }
    }




    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        float alpha = (float)(DateTime.Now - lastUpdateTime).TotalMilliseconds / logicTimer.Interval;
        if (alpha > 1f) alpha = 1f;
        PointF interpolatedPlayerHead = Lerp(prevPlayerSnake[0], playerSnake[0], alpha);
        PointF playerHeadPixel = new PointF(interpolatedPlayerHead.X * cellSize, interpolatedPlayerHead.Y * cellSize);
        PointF cameraOffset = new PointF(playerHeadPixel.X - ClientSize.Width / 2f, playerHeadPixel.Y - ClientSize.Height / 2f);

        g.TranslateTransform(-cameraOffset.X, -cameraOffset.Y);

        float leftWorld = cameraOffset.X;
        float topWorld = cameraOffset.Y;
        float rightWorld = leftWorld + ClientSize.Width;
        float bottomWorld = topWorld + ClientSize.Height;
        int startCol = (int)Math.Floor(leftWorld / cellSize);
        int endCol = (int)Math.Ceiling(rightWorld / cellSize);
        int startRow = (int)Math.Floor(topWorld / cellSize);
        int endRow = (int)Math.Ceiling(bottomWorld / cellSize);
        for (int i = startCol; i <= endCol; i++)
        {
            float x = i * cellSize;
            g.DrawLine(Pens.Gray, x, topWorld, x, bottomWorld);
        }
        for (int j = startRow; j <= endRow; j++)
        {
            float y = j * cellSize;
            g.DrawLine(Pens.Gray, leftWorld, y, rightWorld, y);
        }
        g.DrawRectangle(Pens.Gray, leftWorld, topWorld, ClientSize.Width, ClientSize.Height);

        float boundaryDiameter = mapRadius * 2 * cellSize;
        RectangleF boundaryRect = new RectangleF((mapCenter.X - mapRadius) * cellSize, (mapCenter.Y - mapRadius) * cellSize, boundaryDiameter, boundaryDiameter);
        g.DrawEllipse(Pens.Yellow, boundaryRect);

        DrawSnakeInterpolated(g, prevPlayerSnake, playerSnake, playerBaseColor, true, alpha);

        foreach (var enemy in enemySnakes)
            DrawSnakeInterpolated(g, enemy.PrevSegments, enemy.Segments, enemy.BaseColor, false, alpha);

        foreach (var food in foods)
        {
            PointF prevPos = prevFoodPositions.ContainsKey(food.Id) ? prevFoodPositions[food.Id] : food.Position;
            PointF interpolated = Lerp(prevPos, food.Position, alpha);

            float cx = interpolated.X * cellSize + cellSize / 2f;
            float cy = interpolated.Y * cellSize + cellSize / 2f;

            if (food.IsBigHead)
            {
                float size = cellSize * 2.5f;
                RectangleF foodRect = new RectangleF(cx - size / 2, cy - size / 2, size, size);
                using (GraphicsPath path = new GraphicsPath())
                {
                    path.AddEllipse(foodRect);
                    using (PathGradientBrush pgb = new PathGradientBrush(path))
                    {
                        pgb.CenterColor = Color.Cyan;
                        pgb.SurroundColors = new Color[] { Color.Magenta };
                        g.FillEllipse(pgb, foodRect);
                    }
                }
            }
            else if (food.IsMagnetic)
            {
                float oscillation = (float)(Math.Sin(animationPhase * 2) * 0.5 + 0.5);
                Color magneticColor = InterpolateColor(Color.Red, Color.White, oscillation);
                float size = cellSize * 1.5f;
                RectangleF foodRect = new RectangleF(cx - size / 2, cy - size / 2, size, size);
                using (SolidBrush brush = new SolidBrush(magneticColor))
                    g.FillEllipse(brush, foodRect);
            }
            else if (food.IsSpecial)
            {
                Color oscillatingColor = GetRainbowColor(rainbowPhase + 0.5f);
                RectangleF foodRect = new RectangleF(cx - cellSize, cy - cellSize, cellSize * 2, cellSize * 2);
                using (SolidBrush brush = new SolidBrush(oscillatingColor))
                    g.FillEllipse(brush, foodRect);
            }
            else
            {
                RectangleF foodRect = new RectangleF(interpolated.X * cellSize, interpolated.Y * cellSize, cellSize, cellSize);
                using (SolidBrush brush = new SolidBrush(food.FoodColor))
                    g.FillEllipse(brush, foodRect);
            }
        }

        foreach (var enemy in enemySnakes)
        {
            PointF enemyHead = enemy.Segments[0];
            PointF enemyHeadPixel = new PointF(enemyHead.X * cellSize, enemyHead.Y * cellSize);
            PointF screenPos = new PointF(enemyHeadPixel.X - cameraOffset.X, enemyHeadPixel.Y - cameraOffset.Y);
            g.ResetTransform();
            g.DrawString(enemy.Name, this.Font, Brushes.Black, screenPos);
            g.TranslateTransform(-cameraOffset.X, -cameraOffset.Y);
        }

        g.ResetTransform();
        string scoreText = "Player: " + playerScore;
        g.DrawString(scoreText, this.Font, Brushes.Black, 5, ClientSize.Height - 35);

        if (deathLogEnabled)
        {
            g.ResetTransform();
            int margin = 10;
            float lineHeight = this.Font.GetHeight(g);
            float overlayHeight = lineHeight * deathLog.Count + margin * 2;
            float overlayWidth = 200;
            float overlayX = ClientSize.Width - overlayWidth - margin;
            float overlayY = margin;
            using (SolidBrush backBrush = new SolidBrush(Color.FromArgb(128, Color.Black)))
            {
                g.FillRectangle(backBrush, overlayX, overlayY, overlayWidth, overlayHeight);
            }
            for (int i = 0; i < deathLog.Count; i++)
            {
                g.DrawString(deathLog[i], this.Font, Brushes.White, overlayX + margin, overlayY + margin + i * lineHeight);
            }
        }
    }

    void ShowLeaderboard()
    {
        UsernamePromptForm prompt = new UsernamePromptForm();
        if (prompt.ShowDialog() == DialogResult.OK)
        {
            string username = prompt.Username;
            bool submitSuccess = LeaderboardService.SubmitScore(username, playerScore);
            string leaderboardData = LeaderboardService.GetLeaderboard();
            LeaderboardDisplayForm leaderboardForm = new LeaderboardDisplayForm(leaderboardData);
            leaderboardForm.ShowDialog();
        }
        Application.Exit();
    }
}

//
// CandidateMove struct used for enemy candidate moves.
//
public struct CandidateMove
{
    public float VX;
    public float VY;
    public float Dist;
    public CandidateMove(float vx, float vy, float dist)
    {
        VX = vx;
        VY = vy;
        Dist = dist;
    }
}

//
// Program: Entry point.
//
public static class Program
{
    [STAThread]
    public static void Main()
    {
        Application.EnableVisualStyles();
        Application.Run(new MainMenuForm());
    }
}
