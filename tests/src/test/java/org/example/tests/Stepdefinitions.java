public class StepDefinitions {
    Response response;
    String baseUrl = System.getenv("APP_BASE_URL");


    @When("I call the hello endpoint")
    public void callHello() {
        response = RestAssured.get(baseUrl + "/hello");
    }

    @Then("I receive {string}")
    public void verify(String expected) {
        response.then().body(equalTo(expected));
    }
}