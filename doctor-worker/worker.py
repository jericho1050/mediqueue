#!/usr/bin/env python3
"""
Doctor Worker - Processes patients from the Redis waiting room queue
and records treatment in PostgreSQL.
"""

import json
import os
import sys
import time
from datetime import datetime

import psycopg2
import redis


# Configuration
REDIS_URL = os.environ.get('REDIS_URL', 'redis://localhost:6379')
POSTGRES_URL = os.environ.get('DATABASE_URL', 'postgresql://postgres:postgres@localhost:5432/mediqueue')
QUEUE_NAME = 'waiting_room'
TREATMENT_TIME = int(os.environ.get('TREATMENT_TIME', 5))  # seconds


def parse_redis_url(url):
    """Parse Redis URL into connection parameters."""
    # redis://host:port
    url = url.replace('redis://', '')
    if ':' in url:
        host, port = url.split(':')
        return {'host': host, 'port': int(port)}
    return {'host': url, 'port': 6379}


def connect_redis():
    """Connect to Redis with retry logic."""
    params = parse_redis_url(REDIS_URL)
    max_retries = 10
    retry_delay = 2

    for attempt in range(max_retries):
        try:
            client = redis.Redis(**params, decode_responses=True)
            client.ping()
            print(f"Connected to Redis at {params['host']}:{params['port']}")
            return client
        except redis.ConnectionError as e:
            print(f"Redis connection attempt {attempt + 1}/{max_retries} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                raise


def connect_postgres():
    """Connect to PostgreSQL with retry logic."""
    max_retries = 10
    retry_delay = 2

    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(POSTGRES_URL)
            print("Connected to PostgreSQL")
            return conn
        except psycopg2.OperationalError as e:
            print(f"PostgreSQL connection attempt {attempt + 1}/{max_retries} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                raise


def init_database(conn):
    """Create the medical_records table if it doesn't exist."""
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS medical_records (
        id SERIAL PRIMARY KEY,
        patient_id VARCHAR(36) NOT NULL,
        patient_name VARCHAR(255) NOT NULL,
        condition TEXT NOT NULL,
        admitted_at TIMESTAMP NOT NULL,
        treated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    """

    with conn.cursor() as cur:
        cur.execute(create_table_sql)
        conn.commit()

    print("Database initialized - medical_records table ready")


def process_patient(patient_data, pg_conn):
    """Process a single patient and record in database."""
    try:
        patient = json.loads(patient_data)
        patient_id = patient['id']
        patient_name = patient['name']
        condition = patient['condition']
        admitted_at = patient['admittedAt']

        print(f"\n{'='*50}")
        print(f"Now treating: {patient_name}")
        print(f"Patient ID: {patient_id}")
        print(f"Condition: {condition}")
        print(f"Admitted at: {admitted_at}")
        print(f"Treatment in progress...")

        # Simulate treatment time
        time.sleep(TREATMENT_TIME)

        # Insert into database
        insert_sql = """
        INSERT INTO medical_records (patient_id, patient_name, condition, admitted_at)
        VALUES (%s, %s, %s, %s)
        RETURNING id;
        """

        with pg_conn.cursor() as cur:
            cur.execute(insert_sql, (
                patient_id,
                patient_name,
                condition,
                datetime.fromisoformat(admitted_at.replace('Z', '+00:00'))
            ))
            record_id = cur.fetchone()[0]
            pg_conn.commit()

        print(f"Treatment complete! Record ID: {record_id}")
        print(f"{'='*50}\n")

        return True

    except json.JSONDecodeError as e:
        print(f"Error parsing patient data: {e}")
        return False
    except Exception as e:
        print(f"Error processing patient: {e}")
        pg_conn.rollback()
        return False


def main():
    """Main worker loop."""
    print("\n" + "="*50)
    print("  Doctor Worker Starting")
    print("="*50 + "\n")

    # Connect to services
    redis_client = connect_redis()
    pg_conn = connect_postgres()

    # Initialize database
    init_database(pg_conn)

    print(f"\nWaiting for patients in '{QUEUE_NAME}' queue...")
    print(f"Treatment time: {TREATMENT_TIME} seconds per patient\n")

    patients_treated = 0

    try:
        while True:
            # BRPOP blocks until a patient is available (0 = wait forever)
            result = redis_client.brpop(QUEUE_NAME, timeout=0)

            if result:
                queue_name, patient_data = result
                if process_patient(patient_data, pg_conn):
                    patients_treated += 1
                    print(f"Total patients treated: {patients_treated}")

    except KeyboardInterrupt:
        print("\n\nShutting down doctor worker...")
        print(f"Total patients treated this session: {patients_treated}")
    finally:
        redis_client.close()
        pg_conn.close()
        print("Connections closed. Goodbye!")


if __name__ == '__main__':
    main()
