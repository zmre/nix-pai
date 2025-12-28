// The purpose of this class is to allow the use of thinking models that don't accept levels
// like qwen3:30b-thinking, which will always think but will throw up on think parameters
// Unfortunately, this isn't working as designed at the moment.
// TODO
class StripThinking {
  constructor() {
    this.name = 'strip-thinking';
  }

  async transformRequestIn(request) {
    request.thinking = {
      type: "disabled",
      budget_tokens: -1,
    };
    request.enable_thinking = false;
    return request;
  }

  async transformRequest(request) {
    // Remove the thinking parameter from the request body
    if (request.body) {
      delete request.body.output_config?.effort;
      delete request.body.effort;
      delete request.body.think;
      delete request.body.thinklevel;
      delete request.body.thinking;
      delete request.body.budget_tokens;
    }
    delete request.output_config?.effort;
    delete request.effort;
    delete request.think;
    delete request.thinklevel;
    delete request.thinking;
    delete request.budget_tokens;

    // Anthropic beta headers that might cause issues
    if (request.headers) {
      delete request.headers['anthropic-beta'];
    }
    return request;
  }

  async transformResponse(response) {
    return response;
  }
}

module.exports = StripThinking;
