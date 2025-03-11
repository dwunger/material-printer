using System;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Collections.Generic;

namespace ScreenManager
{
    public static class ConsoleUtils
    {
        public static readonly char ESC = (char)27;
        public static readonly string BOLD = ESC + "[1m";
        public static readonly string UNDERLINE = ESC + "[4m";
        public static readonly string RESET_FMT = ESC + "[0m";
        public static readonly string RED_FG = ESC + "[91m";
        public static readonly string GREEN_FG = ESC + "[92m";
        public static readonly string GRAY_BG = ESC + "[47m";
        public static readonly string BLACK_FG = ESC + "[30m";
    }

    // Shared lock for console output
    public static class ConsoleLock
    {
        public static readonly object Lock = new object();
    }

    public static class ScreenManagerHelper
    {
        public static void SetWindowDimensions(int width, int height)
        {
            Console.WriteLine("Width: " + width);
            Console.WriteLine("Height: " + height);
            if (width <= 0)
                throw new ArgumentException("Width must be a positive integer. Actual value was " + width);
            if (height <= 0)
                throw new ArgumentException("Height must be a positive integer. Actual value was " + height);
            Console.WindowWidth = width;
            Console.WindowHeight = height;
            Console.BufferWidth = width;
            Console.Title = "Rad Printer";
        }
    }

    public class Display
    {
        public int DEBUG_DELAY = 0;
        public List<string> deltabuffer;
        public List<string> frontbuffer;
        public int maxlines = 0;
        public int maxwidth = 0;
        public int line_position;
        public List<string> header;
        public List<string> footer;
        public int content_start;
        public int content_end;

        public Display(int contentLines)
        {
            deltabuffer = new List<string>();
            frontbuffer = new List<string>();
            header = new List<string>();
            footer = new List<string>();
            content_start = 0;
            content_end = contentLines - 1;
            Init(contentLines);
        }

        public void Init(int contentLines)
        {
            for (int i = 0; i < contentLines; i++)
            {
                deltabuffer.Add("");
                frontbuffer.Add("");
            }
        }

        public void SetHeader(List<string> header)
        {
            this.header = header;
            content_start = header.Count;
            UpdateMaxDimensions();
        }

        public void SetFooter(List<string> footer)
        {
            this.footer = footer;
            content_end = frontbuffer.Count - footer.Count - 1;
            UpdateMaxDimensions();
        }

        public void UpdateMaxDimensions()
        {
            var allLines = new List<string>();
            allLines.AddRange(header);
            allLines.AddRange(frontbuffer);
            allLines.AddRange(footer);
            maxlines = allLines.Count;
            maxwidth = (allLines.Count > 0) ? allLines.Max(s => s.Length) : 0;
        }

        public void Clear()
        {
            line_position = content_start;
            UpdateMaxDimensions();
        }

        public void Trim()
        {
            string whiteSpace = new string(' ', maxwidth);
            for (int i = line_position; i <= content_end; i++)
            {
                deltabuffer[i] = whiteSpace;
            }
        }

        public void Write(string newline)
        {
            if (line_position > content_end)
                return;
            if (frontbuffer[line_position] != newline)
                deltabuffer[line_position] = newline;
            line_position++;
        }

        public void Flush()
        {
            string whiteSpace = new string(' ', maxwidth);
            lock (ConsoleLock.Lock)
            {
                // Update header if changed
                for (int i = 0; i < header.Count; i++)
                {
                    if (header[i] != frontbuffer[i])
                    {
                        Console.SetCursorPosition(0, i);
                        Console.Write(whiteSpace);
                        Console.SetCursorPosition(0, i);
                        Console.Write(header[i]);
                        frontbuffer[i] = header[i];
                    }
                }

                // Highlight the first header line
                Console.SetCursorPosition(0, 0);
                Console.ForegroundColor = ConsoleColor.Black;
                Console.BackgroundColor = ConsoleColor.Gray;
                Console.Write(header[0]);
                Console.ResetColor();

                // Update content
                for (int i = content_start; i <= content_end; i++)
                {
                    if (!string.IsNullOrEmpty(deltabuffer[i]))
                    {
                        Console.SetCursorPosition(0, i);
                        Console.Write(whiteSpace);
                        Console.SetCursorPosition(0, i);
                        Console.Write(deltabuffer[i]);
                        frontbuffer[i] = deltabuffer[i];
                        deltabuffer[i] = "";
                    }
                }

                // Update footer if changed
                int footerStart = content_end + 1;
                for (int i = 0; i < footer.Count; i++)
                {
                    if (footer[i] != frontbuffer[footerStart + i])
                    {
                        Console.SetCursorPosition(0, footerStart + i);
                        Console.ForegroundColor = ConsoleColor.Black;
                        Console.BackgroundColor = ConsoleColor.Gray;
                        Console.Write(whiteSpace);
                        Console.SetCursorPosition(0, footerStart + i);
                        Console.Write(footer[i]);
                        Console.ResetColor();
                        frontbuffer[footerStart + i] = footer[i];
                    }
                }
            }
        }
    }

    public class Screen
    {
        public int x;
        public int y;
        public int height;
        public int width;
        // Use the Unicode block by casting its hex code (0x2588)
        protected readonly char borderChar = (char)0x2588;

        public Screen(int x, int y, int width, int height)
        {
            // Ensure Unicode output is set.
            Console.OutputEncoding = Encoding.UTF8;
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;
            Console.Clear();
        }

        protected bool InBounds(int rel_x, int rel_y)
        {
            if (rel_x < 0 || rel_y < 0)
                return false;
            if (rel_y >= height || rel_x >= width)
                return false;
            return true;
        }

        public virtual void Fill(string glyph, int rel_x, int rel_y, int fillWidth, int fillHeight)
        {
            if (!InBounds(rel_x, rel_y) || !InBounds(rel_x + fillWidth - 1, rel_y + fillHeight - 1))
            {
                // Attempted to write out of bounds
                return;
            }
            // Use only the first character of the provided glyph.
            char drawChar = glyph[0];
            // If the caller wants the Unicode block, they can pass borderChar.ToString()
            string line = new string(drawChar, fillWidth);
            lock (ConsoleLock.Lock)
            {
                for (int i = 0; i < fillHeight; i++)
                {
                    Console.SetCursorPosition(x + rel_x, y + rel_y + i);
                    Console.Write(line);
                }
            }
        }

        public virtual void Clear()
        {
            Fill(" ", 0, 0, width, height);
        }

        public virtual void PositionWrite(string str, int rel_x, int rel_y)
        {
            if (!InBounds(rel_x, rel_y))
                return;
            string[] lines = str.Split(new[] { "\n" }, StringSplitOptions.None);
            string stringHead = lines[0];
            string stringTail = (lines.Length > 1) ? string.Join("\n", lines, 1, lines.Length - 1) : "";
            int remainingWidth = this.width - rel_x;
            if (stringHead.Length > remainingWidth)
                stringHead = stringHead.Substring(0, remainingWidth);
            lock (ConsoleLock.Lock)
            {
                Console.SetCursorPosition(x + rel_x, y + rel_y);
                Console.Write(stringHead);
            }
            if (!string.IsNullOrEmpty(stringTail))
                PositionWrite(stringTail, 0, rel_y + 1);
        }

        public virtual void DrawBorder()
        {
            // Use the borderChar for drawing
            Fill(borderChar.ToString(), 0, 0, width, 1);               // Top
            Fill(borderChar.ToString(), 0, 0, 1, height);              // Left
            Fill(borderChar.ToString(), width - 1, 0, 1, height);      // Right
            Fill(borderChar.ToString(), 0, height - 1, width, 1);      // Bottom
        }
    }

    public class StackScreen : Screen
    {
        public List<string> content;
        public bool DISABLE_REFRESH = false;
        public bool HIDE_BORDER = false;
        public string title;

        public StackScreen(int x, int y, int width, int height, string title = "")
            : base(x, y, width, height)
        {
            content = new List<string>();
            this.title = title;
        }

        public void Hide()
        {
            DISABLE_REFRESH = true;
            HIDE_BORDER = true;
            Fill(" ", 0, 0, width, height);
        }

        public void Show()
        {
            DISABLE_REFRESH = false;
            HIDE_BORDER = false;
            Redraw();
            base.DrawBorder();
            if (!string.IsNullOrEmpty(title))
            {
                PositionWrite(title, 2, 0);
            }
        }

        public void PushDown(string newLine)
        {
            string[] lines = newLine.Split(new[] { "\n" }, StringSplitOptions.None);
            content.InsertRange(0, lines);
            if (content.Count > (height - 2)) // account for borders
                content = content.Take(height - 2).ToList();
            if (DISABLE_REFRESH)
                return;
            // Clear content area before redrawing
            Fill(" ", 1, 1, width - 2, height - 2);
            Redraw();
            if (!HIDE_BORDER)
            {
                base.DrawBorder();
                if (!string.IsNullOrEmpty(title))
                {
                    PositionWrite(title, 2, 0);
                }
            }
        }

        public void Redraw()
        {
            if (DISABLE_REFRESH)
                return;
            for (int i = 0; i < content.Count; i++)
                PositionWrite(content[i], 1, i + 1);
            if (!HIDE_BORDER)
            {
                base.DrawBorder();
                if (!string.IsNullOrEmpty(title))
                {
                    PositionWrite(title, 2, 0);
                }
            }
        }

        public string Pop()
        {
            if (content.Count == 0)
                return null;
            string poppedLine = content[0];
            content.RemoveAt(0);
            Fill(" ", 1, 1, width - 2, height - 2);
            Redraw();
            return poppedLine;
        }
    }
}

namespace HuginnNamespace
{
    using ScreenManager;
    using System.Threading;

    public static class Huginn
    {
        public static void EnsurePath(string path)
        {
            string dir = Path.GetDirectoryName(path);
            if (!Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }
        }

        public static string ConvertPathToURI(string path)
        {
            string repoName = QueryParameter("MANIFEST", "GIT_REPO");
            return "https://raw.githubusercontent.com/" + repoName + "/refs/heads/main/" + path;
        }

        public static string QueryParameter(string file, string parameter)
        {
            if (!File.Exists(file))
                throw new FileNotFoundException("Manifest not found: " + file);

            foreach (var line in File.ReadAllLines(file))
            {
                if (line.Contains("="))
                {
                    var parts = line.Split(new char[] { '=' }, 2);
                    if (parts[0].Trim() == parameter)
                        return parts[1].Trim();
                }
            }
            return null;
        }

        public static string FormatPathToSysPath(string path)
        {
            return ".\\" + path.Replace('/', '\\');
        }

        public static async Task<List<string>> GetRemoteIndexPathsAsync(HttpClient client)
        {
            string indexURI = ConvertPathToURI("INDEX");
            string content = await client.GetStringAsync(indexURI);

            var paths = new List<string>();
            foreach (var line in content.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries))
                paths.Add(FormatPathToSysPath(line.Trim()));

            return paths;
        }

        public static async Task<List<string>> GetRemoteIndexURIsAsync(HttpClient client)
        {
            string indexURI = ConvertPathToURI("INDEX");
            string content = await client.GetStringAsync(indexURI);

            var uris = new List<string>();
            foreach (var line in content.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries))
                uris.Add(ConvertPathToURI(line.Trim()));

            return uris;
        }
    }

    public static class HuginnRunner
    {
        // Snack management system humor messages
        private static readonly string[] SnackRepairMessages = new string[]
        {
            "Initializing Snack Management System repair protocol...",
            "WARNING: Snack license expired 42 days ago!",
            "Attempting to bypass snack licensing verification...",
            "Rerouting power to auxiliary snack dispensers...",
            "Reconfiguring quantum snack entanglement matrix...",
            "Bypassing snack integrity checks... Don't tell Gene!",
            "Recompiling snack compiler with deprecated crumb support...",
            "Loading alternative snack recipes from backup...",
            "Patching outdated cookie protocols...",
            "Applying emergency chocolate fix...",
            "Restoring legacy potato chip parameters...",
            "Installing unlicensed snack management firmware...",
            "Snack system partially restored! 42.7% functionality achieved.",
            "Attempting to stabilize the caramel flux capacitor...",
            "Calibrating sugar dispensers to acceptable levels...",
            "Repairing broken pretzel twisting algorithms..."
        };

        // Space-time rift warning messages
        private static readonly string[] RiftWarningMessages = new string[]
        {
            "WARNING: Unauthorized snack repairs may cause space-time anomalies!",
            "CAUTION: Probability of dimensional rift: 12.7% and rising!",
            "ALERT: Quantum snack uncertainty exceeding safe parameters!",
            "WARNING: Unauthorized access to forbidden snack recipes detected!",
            "CAUTION: Temporal anomalies detected in breakroom vicinity!",
            "DANGER: Unshielded snack particle accelerator active!",
            "ALERT: Chocolate-caramel wormhole formation possible!",
            "WARNING: Interdimensional beings may be attracted to unlicensed snacks!",
            "CAUTION: Snack-based reality distortion field expanding!",
            "DANGER: Probability of summoning the Kraken: 27% and rising!",
            "ALERT: Unstable sugar molecules detected in space-time continuum!",
            "WARNING: Do NOT attempt to eat any glowing snacks!",
            "CAUTION: Temporal displacement of missing snacks in progress!",
            "DANGER: Snack-based black hole formation imminent if repairs continue!",
            "ALERT: Unlicensed snack particles merging with dark matter!"
        };

        // Instead of UpdateClientAsync, we now use UpdateClientVerboseAsync.
        public static async Task UpdateClientVerboseAsync(StackScreen downloadScreen, StackScreen snackScreen, StackScreen warningScreen)
        {
            downloadScreen.PushDown("Starting update...");

            // Start background tasks for the snack repair and warning screens
            var snackTask = Task.Run(() => UpdateSnackRepairScreen(snackScreen));
            var warningTask = Task.Run(() => UpdateWarningScreen(warningScreen));

            using (HttpClient client = new HttpClient())
            {
                client.DefaultRequestHeaders.Add("Cache-Control", "no-cache, no-store, must-revalidate");
                client.DefaultRequestHeaders.Add("Pragma", "no-cache");

                var filePathsTask = Huginn.GetRemoteIndexPathsAsync(client);
                var fileURIsTask = Huginn.GetRemoteIndexURIsAsync(client);

                await Task.WhenAll(filePathsTask, fileURIsTask);

                List<string> filePaths = filePathsTask.Result;
                List<string> fileURIs = fileURIsTask.Result;

                var downloadTasks = new List<Task>();

                for (int i = 0; i < fileURIs.Count; i++)
                {
                    string localPath = filePaths[i];
                    string remoteUri = fileURIs[i];

                    downloadTasks.Add(Task.Run(async () =>
                    {
                        downloadScreen.PushDown("Updating: " + localPath);
                        Huginn.EnsurePath(localPath);
                        byte[] data = await client.GetByteArrayAsync(remoteUri);
                        await Task.Run(() => File.WriteAllBytes(localPath, data));
                        downloadScreen.PushDown("Updated: " + localPath);
                    }));
                }

                await Task.WhenAll(downloadTasks);
            }

            downloadScreen.PushDown("Update client completed.");
        }

        private static void UpdateSnackRepairScreen(StackScreen screen)
        {
            foreach (string message in SnackRepairMessages)
            {
                screen.PushDown(message);
                Thread.Sleep(15); // Add a delay between messages
            }
        }

        private static void UpdateWarningScreen(StackScreen screen)
        {
            foreach (string message in RiftWarningMessages)
            {
                screen.PushDown(ConsoleUtils.RED_FG + message + ConsoleUtils.RESET_FMT);
                Thread.Sleep(20); // Slightly longer delay for warnings
            }
        }
    }

    public class Program
    {
        public static void Main(string[] args)
        {
            MainAsync().GetAwaiter().GetResult();
        }

        public static void Main()
        {
            Main(new string[0]);
        }

        private static async Task MainAsync()
        {
            // Set up the console window size.
            try
            {
                ScreenManagerHelper.SetWindowDimensions(120, 40);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error setting window dimensions: " + ex.Message);
            }

            // Initialize the three StackScreens
            StackScreen downloadScreen = new StackScreen(0, 0, 60, 15, "[ FILE DOWNLOAD PROGRESS ]");
            StackScreen snackScreen = new StackScreen(60, 0, 58, 15, "[ SNACK MANAGEMENT SYSTEM REPAIR ]");
            StackScreen warningScreen = new StackScreen(0, 15, 118, 10, "[ SPACE-TIME INTEGRITY WARNINGS ]");

            downloadScreen.DrawBorder();
            snackScreen.DrawBorder();
            warningScreen.DrawBorder();

            // Show titles
            downloadScreen.Show();
            snackScreen.Show();
            warningScreen.Show();

            // Call the verbose method with all three screens
            await HuginnRunner.UpdateClientVerboseAsync(downloadScreen, snackScreen, warningScreen);

            // Wait for user
            Console.SetCursorPosition(0, 30);

        }
    }
}
