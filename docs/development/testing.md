# Running the Test Suite

This guide explains how to set up and run the test suite for the TimescaleDB Ruby gem.

## Prerequisites

### Ruby Version

The test suite requires Ruby 3.3.3 (as specified in `.ruby-version`). The gem itself supports Ruby >= 2.3.0, but the test suite uses Ruby 3.3.3.

You can use a Ruby version manager like `rbenv` or `rvm` to install and manage the correct version:

```bash
# Using rbenv
rbenv install 3.3.3
rbenv local 3.3.3

# Using rvm
rvm install 3.3.3
rvm use 3.3.3
```

### TimescaleDB Installation

You need to have TimescaleDB installed and running. TimescaleDB is a PostgreSQL extension, so you'll need:

1. PostgreSQL installed
2. TimescaleDB extension installed and enabled

For installation instructions, see the [TimescaleDB documentation](https://docs.timescale.com/install/latest/).

### Database Connection

The test suite requires a PostgreSQL database with TimescaleDB enabled. You'll need to:

1. Create a test database (if it doesn't exist)
2. Enable the TimescaleDB extension on that database
3. Set the `PG_URI_TEST` environment variable

## Setup

### 1. Install Dependencies

```bash
bundle install
```

### 2. Configure Database Connection

Set the `PG_URI_TEST` environment variable to point to your test database:

```bash
export PG_URI_TEST="postgresql://username:password@localhost:5432/timescale_test"
```

Or create a `.env` file in the project root:

```bash
PG_URI_TEST=postgresql://username:password@localhost:5432/timescale_test
```

The `.env` file will be automatically loaded by the test suite (via the `dotenv` gem).

### 3. Create and Configure Test Database

Create the test database and enable TimescaleDB:

```bash
# Connect to PostgreSQL
psql -U postgres

# Create the database
CREATE DATABASE timescale_test;

# Connect to the test database
\c timescale_test

# Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit;
```

### 4. Setup Test Tables

Before running tests, you need to set up the test tables. This will create the necessary hypertables and test fixtures:

```bash
bundle exec rake test:setup
```

This command:
- Tears down any existing test tables
- Creates fresh test tables with the correct schema
- Sets up hypertables for testing

**Note:** You should run `rake test:setup` whenever:
- You first set up the test environment
- The test schema changes
- Tests are failing due to missing or incorrect tables

## Running Tests

### Run All Tests

```bash
bundle exec rspec
```

### Run Specific Test Files

```bash
bundle exec rspec spec/timescaledb/migration_helper_spec.rb
```

### Run Specific Tests

```bash
bundle exec rspec spec/timescaledb/migration_helper_spec.rb:114
```

### Run Tests with Output

By default, ActiveRecord SQL logging is silenced. To see SQL queries during tests, set the `DEBUG` environment variable:

```bash
DEBUG=1 bundle exec rspec
```

### Run Only Failed Tests

```bash
bundle exec rspec --only-failures
```

## Troubleshooting

### Database Connection Errors

If you see connection errors, verify:
- PostgreSQL is running
- The database exists
- TimescaleDB extension is enabled
- `PG_URI_TEST` is set correctly

### Missing Tables Errors

If tests fail with "table does not exist" errors, run:

```bash
bundle exec rake test:setup
```

### TimescaleDB Extension Not Found

If you see errors about TimescaleDB functions not being available:
- Verify TimescaleDB is installed: `psql -c "SELECT * FROM pg_extension WHERE extname = 'timescaledb';"`
- Ensure the extension is enabled on your test database
- Check that your PostgreSQL version is compatible with your TimescaleDB version

### Timescale Toolkit Not Installed

Occasionally you may see numerous failures related to functions being undefined within TimescaleDB. To resolve this, ensure you have the [TimescaleDB Toolkit](https://github.com/timescale/timescaledb-toolkit) plugin installed and enabled

## Continuous Integration

The test suite is designed to work in CI environments. Make sure your CI configuration:

1. Sets the `PG_URI_TEST` environment variable
2. Has TimescaleDB installed and enabled
3. Runs `bundle exec rake test:setup` before running tests

