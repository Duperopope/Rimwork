namespace RimWorldLab
{
    public static class MathUtils
    {
        public static double CalculateRatio(double numerator, double denominator)
        {
            if (denominator == 0.0)
            {
                return 0.0; // Handle division by zero gracefully
            }
            return numerator / denominator;
        }
    }
}
