// Значок застосунку «Графік світла» для iPhone: 1024×1024 без прозорості (App Store прозорих значків не приймає).
// Будинок із вікнами-годинами, як типовий вигляд віджета, на темно-синьому тлі палітри B; рамка — «зараз».
// Запуск (JDK уже є в android/.tools):
//   android/.tools/jdk/bin/java ios/tools/AppIcon.java ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import java.awt.Color;
import java.awt.GradientPaint;
import java.awt.Graphics2D;
import java.awt.RadialGradientPaint;
import java.awt.RenderingHints;
import java.awt.BasicStroke;
import java.awt.geom.Point2D;
import java.awt.geom.RoundRectangle2D;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

public class AppIcon {
    public static void main(String[] args) throws Exception {
        int s = 1024;
        BufferedImage img = new BufferedImage(s, s, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
        g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);

        // Тло: темно-синій діагональний градієнт і мʼяке тепле світіння за будинком.
        g.setPaint(new GradientPaint(0, 0, new Color(0x3E4378), s, s, new Color(0x1B1E38)));
        g.fillRect(0, 0, s, s);
        g.setPaint(new RadialGradientPaint(new Point2D.Float(s * 0.5f, s * 0.56f), s * 0.48f,
            new float[] {0f, 1f}, new Color[] {new Color(255, 194, 51, 64), new Color(255, 194, 51, 0)}));
        g.fillRect(0, 0, s, s);

        // Будинок: димар, стіна з вертикальним градієнтом.
        float hx = s * 0.22f, hy = s * 0.27f, hw = s * 0.56f, hh = s * 0.54f;
        g.setPaint(new Color(0x5A6089));
        g.fill(new RoundRectangle2D.Float(hx + hw * 0.18f, hy - s * 0.075f, hw * 0.22f, s * 0.13f, 28, 28));
        g.setPaint(new GradientPaint(0, hy, new Color(0x868CB1), 0, hy + hh, new Color(0x5F6593)));
        g.fill(new RoundRectangle2D.Float(hx, hy, hw, hh, 72, 72));

        // Вікна 2 × 3: горять (бурштин), темні (без світла); біле обрамлення — поточна година.
        boolean[][] lit = {{true, true}, {true, false}, {false, true}};
        float padX = hw * 0.14f, padY = hh * 0.1f, gap = hw * 0.1f;
        float ww = (hw - 2 * padX - gap) / 2;
        float wh = (hh - 2 * padY - 2 * gap * 0.8f) / 3;
        for (int row = 0; row < 3; row++) {
            for (int col = 0; col < 2; col++) {
                float x = hx + padX + col * (ww + gap);
                float y = hy + padY + row * (wh + gap * 0.8f);
                RoundRectangle2D.Float w = new RoundRectangle2D.Float(x, y, ww, wh, ww * 0.36f, ww * 0.36f);
                if (lit[row][col]) {
                    for (int i = 6; i >= 1; i--) { // світіння
                        float e = i * 7f;
                        g.setPaint(new Color(255, 194, 51, 14));
                        g.fill(new RoundRectangle2D.Float(x - e, y - e, ww + 2 * e, wh + 2 * e, ww * 0.36f + e, ww * 0.36f + e));
                    }
                    g.setPaint(new GradientPaint(0, y, new Color(0xFFD660), 0, y + wh, new Color(0xFFB52A)));
                } else {
                    g.setPaint(new Color(0x343A66));
                }
                g.fill(w);
                if (row == 1 && col == 0) {
                    g.setPaint(Color.WHITE);
                    g.setStroke(new BasicStroke(s * 0.016f));
                    float o = s * 0.018f;
                    g.draw(new RoundRectangle2D.Float(x - o, y - o, ww + 2 * o, wh + 2 * o, ww * 0.36f + o * 2, ww * 0.36f + o * 2));
                }
            }
        }
        g.dispose();
        File out = new File(args.length > 0 ? args[0] : "AppIcon.png");
        if (out.getParentFile() != null) out.getParentFile().mkdirs();
        ImageIO.write(img, "png", out);
        System.out.println("Значок: " + out.getPath() + " (" + s + "×" + s + ")");
    }
}
