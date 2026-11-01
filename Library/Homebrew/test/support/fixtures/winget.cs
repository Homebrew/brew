using System;
using System.Globalization;
using System.IO;
using System.Text;

public class WinGetFixture
{
    public static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        string configuration = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "exit-code.txt");
        uint status = uint.Parse(File.ReadAllText(configuration), NumberStyles.HexNumber);
        Console.Error.WriteLine("native diagnostic café");

        if (status == 0)
        {
            if (args[0] == "export")
            {
                string output = args[Array.IndexOf(args, "--output") + 1];
                File.WriteAllText(output,
                    "{\"Sources\":[{\"Packages\":[{\"PackageIdentifier\":\"Example.App\"}]}]}",
                    new UTF8Encoding(false));
            }
            else
            {
                Console.WriteLine("Name                Id                  Version\n" +
                    "------------------------------------------------\n" +
                    "Example café        Example.App         1.0");
            }
        }

        return unchecked((int)status);
    }
}
