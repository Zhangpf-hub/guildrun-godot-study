using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using AssetStudio;

// Build against the Windows .NET Framework AssetStudioMod 0.20 assemblies.
// Each plan row contains the Animator ID and its resolved (overridden) clip IDs.
internal static class ExportCharacterAnimations
{
    private static void Main(string[] args)
    {
        var manager = new AssetsManager();
        manager.LoadFilesAndFolders(args[0]);
        var file = manager.AssetsFileList.First(f => Path.GetFileName(f.fullName) == Path.GetFileName(args[0]));
        foreach (string line in File.ReadLines(args[1]))
        {
            string[] columns = line.Split('\t');
            var animator = (Animator)file.ObjectsDic[long.Parse(columns[0])];
            var clips = columns[1].Split(',').Select(id => (AnimationClip)file.ObjectsDic[long.Parse(id)]).ToList();
            string directory = Path.Combine(args[2], columns[0]);
            Directory.CreateDirectory(directory);
            var model = new ModelConverter(animator, ImageFormat.Png, clips);
            var settings = new Fbx.Settings { BoneSize = 1, ScaleFactor = 100, ExportAnimations = true };
            ModelExporter.ExportFbx(Path.Combine(directory, "model.fbx"), model, settings);
            Console.WriteLine("{0}: {1} bound clips", columns[0], clips.Count);
        }
    }
}
