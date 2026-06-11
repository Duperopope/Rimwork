namespace RimWorldLab
{
    public static class Utility
    {
        public static string Combine(params string[] parts)
        {
            return string.Join(" ", parts);
        }
    }
}
