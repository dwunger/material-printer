using System;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Collections.Generic;

namespace HuginnNamespace
{
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
                    var parts = line.Split(new char[] {'='}, 2);
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
        public static async Task UpdateClientAsync()
        {
            Console.WriteLine("Starting update...");

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
                        Console.WriteLine("Updating: " + localPath);
                        Huginn.EnsurePath(localPath);
                        byte[] data = await client.GetByteArrayAsync(remoteUri);
                        await Task.Run(() => File.WriteAllBytes(localPath, data));
                        Console.WriteLine("Updated: " + localPath);
                    }));
                }

                await Task.WhenAll(downloadTasks);
            }

            Console.WriteLine("Update client completed.");
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
            await HuginnRunner.UpdateClientAsync();
        }
    }
}
