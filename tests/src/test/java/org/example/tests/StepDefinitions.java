package org.example.tests;

import io.cucumber.java.en.When;
import io.cucumber.java.en.Then;

import io.restassured.RestAssured;
import io.restassured.response.Response;

import static org.hamcrest.Matchers.equalTo;

public class StepDefinitions {
    Response response;
    String baseUrl = System.getenv("APP_BASE_URL");

    @When("I call the hello endpoint")
    public void callHello() {
        response = RestAssured
                .given()
                .relaxedHTTPSValidation()
                .get(baseUrl + "/hello");
    }

    @Then("I receive {string}")
    public void verify(String expected) {
        response.then().body(equalTo(expected));
    }
}
