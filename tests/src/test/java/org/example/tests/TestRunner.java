import io.cucumber.junit.Cucumber;
import io.cucumber.junit.CucumberOptions;
import org.junit.runner.RunWith;

@RunWith(Cucumber.class)
@CucumberOptions(
        features = "src/test/resources/features",
        glue = "org.example.tests",
        plugin = {
                "pretty",
                "junit:target/surefire-reports/cucumber-results.xml"
        }
)
public class TestRunner {
}
