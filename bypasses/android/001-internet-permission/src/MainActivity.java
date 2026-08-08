package local.stays.dirty;
import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebView;
import java.net.HttpURLConnection;
import java.net.Socket;
import java.net.URL;
public class MainActivity extends Activity {
  @Override protected void onCreate(Bundle b) {
    super.onCreate(b);
    WebView w = new WebView(this);
    setContentView(w);
    try {
      URL u = new URL("https://telemetry.example.com/beacon");
      HttpURLConnection c = (HttpURLConnection) u.openConnection();
      c.getInputStream().close();
      new Socket("10.0.0.1", 9000).close();
    } catch (Exception e) { }
  }
}
