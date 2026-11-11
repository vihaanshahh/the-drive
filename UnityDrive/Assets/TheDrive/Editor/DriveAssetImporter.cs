using UnityEditor;
using UnityEngine;

namespace TheDrive.UnityGame.Editor
{
    /// <summary>Import the original bottom-origin atlas and normal maps for the built-in Standard shader.</summary>
    public sealed class DriveAssetImporter : AssetPostprocessor
    {
        void OnPreprocessTexture()
        {
            if (!assetPath.Contains("TheDrive/Resources/Drive/")) return;
            var importer = (TextureImporter)assetImporter;
            importer.mipmapEnabled = !assetPath.Contains("/Art/");
            importer.maxTextureSize = 2048;
            importer.textureCompression = assetPath.Contains("/Art/")
                ? TextureImporterCompression.Uncompressed : TextureImporterCompression.CompressedHQ;
            importer.wrapMode = assetPath.Contains("/Art/") ? TextureWrapMode.Clamp : TextureWrapMode.Repeat;
            if (assetPath.EndsWith("-normal.png")) {
                importer.textureType = TextureImporterType.NormalMap;
                importer.sRGBTexture = false;
            } else if (assetPath.Contains("-metallic-roughness") || assetPath.Contains("-standard-metallic")) {
                importer.textureType = TextureImporterType.Default;
                importer.sRGBTexture = false;
                importer.alphaSource = TextureImporterAlphaSource.FromInput;
            } else {
                importer.textureType = TextureImporterType.Default;
                importer.sRGBTexture = true;
            }
        }
    }
}
