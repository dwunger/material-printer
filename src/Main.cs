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
// Leaderboard loading is deferred until after the form is shown.
//
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

        // Instructions label.
        Label instructionsLabel = new Label();
        instructionsLabel.Text = "Controls:\n- Move snake with mouse (WASD/Arrow keys override).\n- Press Space or hold mouse down to boost (costs 1 segment/tick).\n- Magnetic and special food trigger unique effects.\n- Escape to pause";
        instructionsLabel.Location = new Point(20, 20);
        instructionsLabel.Size = new Size(280, 150);
        instructionsLabel.Font = new Font("Arial", 10);
        instructionsLabel.AutoSize = false;

        // Changelog group box.
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

        // Start game button.
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

        // Leaderboard group box.
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

        // Add controls.
        this.Controls.Add(instructionsLabel);
        this.Controls.Add(changelogBox);
        this.Controls.Add(leaderboardBox);
        this.Controls.Add(startButton);

        // Defer leaderboard loading until the form is shown.
        this.Shown += MainMenuForm_Shown;
    }

    private void MainMenuForm_Shown(object sender, EventArgs e)
    {
        // Now that the form is visible, load the leaderboard data.
        string leaderboardData = LeaderboardService.GetLeaderboard();
        List<LeaderboardEntry> entries = ParseLeaderboardData(leaderboardData);
        leaderboardGrid.DataSource = entries;
    }

    // Copy of the manual JSON parsing logic.
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
    // [GameForm code remains unchanged...]
    // For brevity, assume the complete GameForm implementation remains as provided.
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
