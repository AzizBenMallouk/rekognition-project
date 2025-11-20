import os
import json
import logging
from datetime import datetime, timezone
from urllib.parse import unquote_plus

import boto3
import pymysql

logger = logging.getLogger()
logger.setLevel(logging.INFO)

session = boto3.session.Session()
AWS_REGION = os.getenv("AWS_REGION", session.region_name or "us-east-1")

rek = boto3.client("rekognition", region_name=AWS_REGION)

COLLECTION_ID = os.environ["COLLECTION_ID"]
TABLE_NAME = os.getenv("TABLE_NAME", "uploads")

DB_HOST = os.environ["DB_HOST"]
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.environ["DB_USER"]
DB_PASS = os.environ["DB_PASS"]
DB_NAME = os.environ["DB_NAME"]


def _get_db_conn():
    conn = pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        connect_timeout=10,
        cursorclass=pymysql.cursors.DictCursor,
    )
    return conn


def _ensure_table(conn):
    create_sql = f"""
    CREATE TABLE IF NOT EXISTS {TABLE_NAME} (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        s3_bucket VARCHAR(255) NOT NULL,
        s3_key TEXT NOT NULL,
        rekognition_faces JSON NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_{TABLE_NAME}_s3_bucket (s3_bucket),
        KEY idx_{TABLE_NAME}_s3_key (s3_key(191))
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """
    with conn.cursor() as cur:
        cur.execute(create_sql)
    conn.commit()


def _insert_row(conn, s3_bucket, s3_key, faces_json):
    insert_sql = f"""
    INSERT INTO {TABLE_NAME} (s3_bucket, s3_key, rekognition_faces, created_at)
    VALUES (%s, %s, %s, %s);
    """
    with conn.cursor() as cur:
        cur.execute(
            insert_sql,
            (s3_bucket, s3_key, json.dumps(faces_json), datetime.now(timezone.utc)),
        )
    conn.commit()


def _index_faces(bucket: str, key: str):
    external_id = key.split("/")[-1]
    resp = rek.index_faces(
        CollectionId=COLLECTION_ID,
        Image={"S3Object": {"Bucket": bucket, "Name": key}},
        ExternalImageId=external_id,
        DetectionAttributes=["DEFAULT"],
        QualityFilter="AUTO",
        MaxFaces=10,
    )

    face_records = resp.get("FaceRecords", [])
    unindexed = resp.get("UnindexedFaces", [])

    result = {
        "indexed_count": len(face_records),
        "face_ids": [fr["Face"]["FaceId"] for fr in face_records],
        "image_id": face_records[0]["Face"]["ImageId"] if face_records else None,
        "unindexed_reasons": [
            reason
            for uf in unindexed
            for reason in uf.get("Reasons", [])
        ],
    }
    return result


def lambda_handler(event, context):
    logger.info("Received event:\n%s", json.dumps(event, indent=2))

    records = event.get("Records", [])
    if not records:
        logger.warning("No Records found in event. Nothing to do.")
        return {"statusCode": 200, "body": json.dumps({"message": "No records"})}

    conn = None
    try:
        conn = _get_db_conn()
        _ensure_table(conn)

        processed = []

        for rec in records:
            s3 = rec.get("s3", {})
            bucket = s3.get("bucket", {}).get("name")
            key = s3.get("object", {}).get("key")

            if not bucket or not key:
                logger.warning("Skipping record missing bucket or key: %s", json.dumps(rec))
                continue

            key = unquote_plus(key)
            logger.info("Processing s3://%s/%s", bucket, key)

            faces = _index_faces(bucket, key)
            logger.info("Rekognition result: %s", json.dumps(faces))

            _insert_row(conn, bucket, key, faces)

            processed.append(
                {
                    "bucket": bucket,
                    "key": key,
                    "rekognition": faces,
                }
            )

        return {
            "statusCode": 200,
            "body": json.dumps({"processed": processed}),
        }

    except Exception as e:
        logger.exception("Error in processing: %s", e)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
    finally:
        if conn is not None:
            conn.close()
