# Introduction to AI Agents

Artificial Intelligence (AI) agents are programs capable of autonomous actions in an environment to meet specific goals. These agents can analyze their environment, make decisions, and execute actions independently. Many industries leverage AI to automate processes, improve customer interaction, provide personalized recommendations, and more.

One common way of interacting with AI agents is through an Application Programming Interface (API). An API provides a set of rules and protocols for interacting with a software application. In the context of AI, APIs often allow developers to leverage complex machine learning models in their applications without needing to understand all the underlying details.

Through APIs, we can instruct AI to play various roles within our business. For example, an AI agent could act as a customer service representative, answering common queries and providing information to customers 24/7. Alternatively, it could play a role in data analysis, interpreting raw data and providing valuable insights.

# Converting Human Language to SQL Queries

A fascinating application of AI is the capability to understand and interpret human language, a field known as Natural Language Processing (NLP). Using AI, we can convert natural language into structured queries, such as SQL, on the fly. This means we can interact with our databases using everyday language rather than needing to write complex queries.

For example, a user could ask an AI agent, "How many users signed up in the last week?" The AI agent can convert this question into an SQL query to retrieve the answer from the database. This capability can dramatically simplify interactions with databases and make data more accessible to non-technical users.

In this example, we used an AI (GPT-4 by OpenAI) to interact with the user, interpret the user's instructions, convert these instructions into SQL queries, and then execute these queries on a TimescaleDB database. This is an example of how AI can serve as a 'middle-man', simplifying the interface between humans and databases.

# Using Open AI as a long term memory

The process of long term memory is nothing else than stacking more chat
conversation to the API, similar to what the chat.openai.com uses to group by
conversations by topic and building this space to save the context.

Using the API it's more about persisting the actual messages and then sending it
along with the actual prompt.

# Setting up initial instructions to the AI agent

Here is the initial instructions we'll always send to the API to guarantee it
knows it has access to the database and it can execute queries or consult the
catalog in case it does not know exactly the information that is necessary to
achieve the result.

    As an AI language model, you have access to a TimescaleDB database that stores conversation history in a table called "conversations". You can execute SQL queries to retrieve information from this table using markdown language. Use the common backticks with sql as the language and you'll have access to any information you need. Results of multiple queries will be answered in the same order.

    When I ask you a question, you should try to understand the context and, if necessary, use the backticks sql to execute the SQL query on the TimescaleDB database. Please provide the information I requested based on the query results. Always use one query per snippet.

    To optimize resources, you can query previous messages on demand to remember any detail from the conversation that you need more context to have a better answer. When you have more to say, just continue. Everything is being written to the conversations hypertable. You can query any time you need to know more about an specific context.

    Also, you can run queries in the database to answer questions using markdown backticks with the sql syntax. For example:

    If I ask, "How many conversations have I had today?", you could respond with:

    ```sql
    SELECT COUNT(*)
    FROM conversations
    WHERE topic = '#{topic}'
    AND DATE(ts) = CURRENT_DATE;
    ```

    The extra conversations columns are user_input and ai_response.

    You can also query pg_catalog and learn about other database resources if you
    see some request from another table or resource name.

    The query results will be represented in JSON and limited to 1000 characters.

    Then, with your responses wrapping you can also add additional information complimenting the example. All results will be answered numbering the same sequence of queries found in the previous answer. Always choose to answer in markdown format and I'll always give the results in markdown format too.


## Setup the environment

Our plan is use Ruby to interact with OpenAI's GPT-4 and TimescaleDB. The program will
be emulating a chat interface that can execute SQL code from API responses and build
SQL commands and interact with a Postgresql using natural language.

Make sure you have a `.envrc` file and a tool like [direnv](https://direnv.net).


```bash
export GPT4_KEY=<put-your-api-key-here>
export PG_URI=postgres://jonatasdp@localhost:5432/chatgpt-demo
```

If you don't have the `GPT4_KEY`, you can get it [here](https://platform.openai.com/account/api-keys).

Make sure you adjust the `PG_URI` with your postgresql instance connection, and if you don't have a database instance locally, you can also setup one on the [Timescale cloud](https://timescale.com/products#cloud) very easily.

## Requirements

Ruby is the language that will run in the backend to connect to the OpenAI API
and to the Postgresql instance. It will be a single file with everything inside.

If you just want to run it, here is the [final file][open-api-cli].

We use `bundler/inline` to manage gem dependencies. Here are the required gems:

```ruby
gem 'timescaledb' # A wrapper to interact with TimescaleDB.
gem 'rest-client' # Simple HTTP and REST client for Ruby.
gem 'pry' # A runtime developer console to iterate and inspect the code.
gem 'markdown' # Ruby Markdown parser.
gem 'rouge' # A pure Ruby code highlighter.
gem 'redcarpet' # A Ruby library for Markdown processing.
gem 'tty-markdown' # A Markdown parser with syntax highlighting.
gem 'tty-link' # To make URLs clickable in the terminal.
```

## Main Code

First, require the necessary libraries:

```ruby
require 'json'
require 'time'
```

We'll be using API keys and URI's defined in environment variables:

```ruby
API_KEY = ENV['GPT4_KEY']
PG_URI = ENV['PG_URI'] || ARGV[ARGV.index("--pg-uri")]
```

## Persist history in the conversation model

We then define a `Conversation` class that interacts with TimescaleDB:

```ruby
class Conversation < ActiveRecord::Base
  self.primary_key = nil
  acts_as_hypertable
  ...
end
```

## Extract SQL from API responses

When the API calls back suggesting some sql blocks, we're going to detect them
by converting the markdown response into a html and then checking the html
blocks.

And an `SQLExtractor` class to extract SQL from markdown. This class will be
stacking all markdown blocks to be executed later.

```ruby
class SQLExtractor < Redcarpet::Render::Base
  attr_reader :sql
  def block_code(code, language)
    if language == 'sql'
      @sql ||= []
      @sql << code
      code
    else
      ""
    end
  end
end
```

## Call GPT4 API from the Ruby code

The `call_gpt4_api` method is used to call the GPT-4 API with a prompt.
At this moment we need to stack the following information:

1. Role assignment: Initial instructions saying it's an AI agent - info that assigns the role of the API in this call.
2. Context: Previous User Input + AI Responses in the same topic.
3. User Input: what user is asking now.

```ruby
def call_gpt4_api(prompt)
  url = "https://api.openai.com/v1/chat/completions"
  full_prompt = INSTRUCTIONS +
      "\nHistory: #{Conversation.history}" +
      "\nInput: #{prompt}"

  body = { "model" => "gpt-4",
      "max_tokens" => 1000,
      "temperature" => 0,
      "messages" => [{"role" => "user", "content" => full_prompt}],
    }.to_json
  headers = { "Content-Type" => "application/json", "Authorization" => "Bearer #{API_KEY}" }
  response = RestClient.post(url, body, headers)
  json_response = JSON.parse(response.body)
  response = json_response["choices"].first["message"]["content"].strip
rescue RestClient::BadRequest
  "Bad Request Error: #{$!.message}"
rescue
  "Error: #{$!.message}"
end
```

## Execute queries in the database

As the API responses can bring queries and the SQLExtractor can detect them, now
it's time to have a method to be executing the SQL queries and returning error
messages in case it fails, so the API can recursively try to fix the issue.

The following method try to execute the query and return high level error messages in case
the execution fails:

```ruby
def execute(query)
  begin
    ActiveRecord::Base.connection.execute(query)
  rescue => e
    "Query Error: #{e.message}"
  end
end
```

!!!info "Truncating query results"

    As the AI has access to the database, sometimes the query results are quite
    heavy and then it really slows down the upstreaming and processing of the
    context. So, for now, I'm truncating the results in 10k characters.

    It reduced a lot the timeouts and still quite good and working well.

    ```ruby
    json = execute(sql).to_json
    results << json
    if json.length > 10000
      json = json[0..10000]+"... (truncated)"
    end
    ```

## Establishing the chat

In the high level, we need to keep interacting with the user until they give up.

In `chat_mode` method, we loop to continuously get user input and interact with GPT-4:

```ruby
def chat_mode
  info WELCOME_INFO
  timeout = 300 # Set the timeout in seconds

  loop do
    print "\n#{topic}: "
    input = if IO.select([STDIN], [], [], timeout)
              STDIN.gets.chomp
            else
              puts "Timeout reached, exiting chat."
              break
            end

    case input.downcase
    when 'quit'
      puts "Exiting chat."
      break
    when 'debug'
      require "pry";binding.pry
    else
      with_no_logs do
        chat(input)
      end
    end
  end
end
```

!!!info "Colored markdown"

    To parse Markdown and have a colored markdown in the command line, use the
    magical tty-markdown library:

    ```ruby
    def info(content)
      puts TTY::Markdown.parse(content)
    end
    ```

In `chat` method, we get the response from GPT-4, create a conversation record
and then execute SQL queries from the markdown:

```ruby
def chat(prompt)
  response = call_gpt4_api(prompt)
  with_no_logs do
    Conversation.create(topic: topic,
                        user_input: prompt,
                        ai_response: response,
                        ts: Time.now)
  end

  info("**AI:** #{response}")

  queries = sql_from_markdown(response)

  if queries&.any?
    output = run_queries(queries)

    info(output)
    chat(output)
  end
end
```

To run the queries, you can also eval some context like the `topic`.

```ruby
def run_queries(queries)
  queries.each_with_index.map do |query,i|
    sql = query.gsub(/#\{(.*)\}/){eval($1)}

    json = execute(sql).to_json
    json = json[0..10000]+"... (truncated)" if json.length > 10000
    <<~MARKDOWN
      Result from query #{i+1}:
      #{json}
    MARKDOWN
  end.join("\n")
end
```

!!!warning "eval is evil 😈"
    Note that we're using:
    ```ruby
    eval($1)
    ```
    It will capture the result of the query param that is wrapped with `#{}`
    and execute it in the context. It's useful to guarantee we're filtereing by
    the topic and keep it simple for the example. If you want to build a
    production code make sure you use a more robust and safe approach for it.



We'll also define the `topic` which will be used as a command line argument or
just assigning the USER name as the default topic to group conversations.

```ruby
def topic
  ARGV[1] || ENV['USER']
end
```

The instructions described before are also avaialable in the same [example
folder][example] and was used as a raw text. You can also override and test with
different subjects and evolve from some in progress research as well.

```ruby
def instructions
  if File.exists?(ARGV.last)
    ARGV.last
  else
    'instructions.md'
  end
end
```

As a final step, setup the conversations table and enable the extension if
necessary.

```ruby
def setup_schema
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  ActiveRecord::Base.establish_connection(PG_URI)

  # Create the events table if it doesn't exist
  unless Conversation.table_exists?
    ActiveRecord::Base.connection.instance_exec do
      execute "CREATE EXTENSION IF NOT EXISTS timescaledb"
      create_table :conversations, id: false, hypertable: {time_column: :ts} do |t|
        t.timestamptz :ts, default: "now()", null: false
        t.string :topic, null: false
        t.text :user_input, null: false
        t.text :ai_response, null: false
      end
    end
  end
end
```

The main method is where we establish the connection and start the chat mode and
we can call it right after the definition in the body of the ruby file.

```ruby
def main
  setup_schema
  chat_mode
end

main
```

## Extra capabilities

I initially build it for queries but trying to request several database tasks, 
I was also able to enable compression, create continuous aggregates, add
retention policies and also refresh continuous aggregates policies.

### Enable compression for a hypertable

I started trying this out. Asking it to enable compression, and here is the
interaction output.

The following example show an interaction which will execute the sql query:

```
User: enable compression for the conversations hypertable
AI: To enable compression for the “conversations” hypertable in TimescaleDB,
you would need to execute an ALTER TABLE command with the SET function to
enable compression. However, as an AI language model, I don’t have the ability
to execute SQL commands directly on a database.

Here’s an example of how you could do it:

    ALTER TABLE conversations SET (
      timescaledb.compress,
      timescaledb.compress_segmentby = 'user_input'
    );


This command will enable compression on the “conversations” hypertable and set the ‘user_input’ column as the segment by option. The ‘compress_segmentby’ option determines how the data will be ordered during compression, which can improve query performance.

Please note that you should replace ‘user_input’ with the appropriate column name based on your specific use case. Also, remember to execute this command as a user with the necessary
privileges.
```

The example from the output will be executed by the command line in the database
that you're connected. And the API response also follow with more instructions
and recursively interact in case multiple back and forth are necessary.

### Create continuous aggregates

Now, let's dive into [continuous aggregates](https://docs.timescale.com/api/latest/continuous-aggregates/create_materialized_view/#continuous-aggregates) feature and ask to create the first materialized view for it.

```
User: create a continuous aggregate materialized view summarizing number of
words from user_input and ai_response grouped by 1 hour.
AI: Sure, to create a continuous aggregate materialized view that summarizes
the number of words from user_input and ai_response grouped by 1 hour,
you can use the following SQL command:

    CREATE MATERIALIZED VIEW conversation_summary
    WITH (timescaledb.continuous) AS
    SELECT time_bucket(INTERVAL '1 hour', ts) AS one_hour,
        COUNT(*) AS total_conversations,
        SUM(LENGTH(user_input) - LENGTH(REPLACE(user_input, ' ', '')) + 1) AS user_input_words,
        SUM(LENGTH(ai_response) - LENGTH(REPLACE(ai_response, ' ', '')) + 1) AS ai_response_words
    FROM conversations
    GROUP BY one_hour;

This command creates a materialized view named conversation_summary that groups the conversations by each hour. It also calculates the number of words in user_input and ai_response by counting the number of spaces and adding 1 (assuming words are separated by a single space).

Please note that this command should be executed by someone with the necessary permissions in the database. Also, the actual creation of the view might take some time depending on the size of the conversations table.
```

You can also try to setup retention policies  or create new hypertables if you
want. It seems very flexible and safe to use in a sandbox to explore data.

### Complex query building

It's also very good on building more complex queries, especially after adding
more examples about it.

## Knowing issues

While you can easily get some snippets, from time to time, if you change the
subject, things will get complicated and it will commit several errors in a row.

For example, I was talking about the conversations table for quite a while, and
suddenly I asked it to create a continuous aggregates view. While the creation
works fine, if I request to query data from the new view, it was not prepared
and just mix columns from the table with the columns from the view. I tried
several examples and it was not able to get it properly. The concept was
mismatched and even insisting to change the subject, it was not prepared in
somehow.

## Try it yourself

If you want to try it, this example is available on
[examples/chatgpt/openai-cli.rb][open-api-cli] and you can follow the
instructions in the folder how to use it.

[open-api-cli]: https://github.com/timescale/timescaledb-ruby/blob/main/examples/chatgpt/openai-cli.rb
