public class MainMenuForm : Form
{
    private DataGridView leaderboardGrid;

    public MainMenuForm()
    {
        this.Text = "Snek Menu - Version 1.1.4";
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
        changelogLabel.Text = "Version 1.1.5:\n- Added pause\n- Added leaderboard!";
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
