import os
import json
import logging
from urllib.parse import unquote_plus
import urllib.request

import boto3
import pymysql

logger = logging.getLogger()
logger.setLevel(logging.INFO)

session = boto3.session.Session()
AWS_REGION = os.getenv("AWS_REGION", session.region_name or "us-east-1")

rek = boto3.client("rekognition", region_name=AWS_REGION)

COLLECTION_ID = os.environ["COLLECTION_ID"]
TABLE_NAME = os.getenv("TABLE_NAME", "uploads")
UI_NOTIFY_URL = os.environ["UI_NOTIFY_URL"]

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


def _search_faces(bucket, key):
    resp = rek.search_faces_by_image(
        CollectionId=COLLECTION_ID,
        Image={"S3Object": {"Bucket": bucket, "Name": key}},
        FaceMatchThreshold=80,
        MaxFaces=10,
    )
    return resp.get("FaceMatches", [])


def _get_slug_for_face_id(conn, face_id: str):
    sql = f"""
    SELECT s3_key
    FROM {TABLE_NAME}
    WHERE rekognition_faces LIKE %s
    LIMIT 1;
    """
    with conn.cursor() as cur:
        cur.execute(sql, (f"%{face_id}%",))
        row = cur.fetchone()

    if not row:
        return None

    s3_key = row["s3_key"]
    parts = s3_key.split("/")
    if len(parts) < 3:
        return None

    slug = parts[1]
    return slug


def _notify_ui(socket_id: str, people):
    if not UI_NOTIFY_URL:
        logger.warning("UI_NOTIFY_URL not set, skipping notify")
        return

    payload = json.dumps({
        "socketId": socket_id,
        "people": list(people),
    }).encode("utf-8")

    req = urllib.request.Request(
        UI_NOTIFY_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=3) as resp:
        logger.info("Notify UI status: %s", resp.status)


def lambda_handler(event, context):
    logger.info("Received event:\n%s", json.dumps(event, indent=2))

    records = event.get("Records", [])
    if not records:
        return

    rec = records[0]
    s3_info = rec.get("s3", {})
    bucket = s3_info.get("bucket", {}).get("name")
    key = s3_info.get("object", {}).get("key")

    if not bucket or not key:
        logger.warning("Missing bucket/key in event record.")
        return

    key = unquote_plus(key)
    logger.info("Processing s3://%s/%s", bucket, key)

    parts = key.split("/")
    socket_id = parts[1] if len(parts) >= 3 else None
    if not socket_id:
        logger.warning("Could not determine socketId from key=%s", key)

    face_matches = _search_faces(bucket, key)

    conn = _get_db_conn()
    people = set()
    try:
        for m in face_matches:
            face = m.get("Face", {})
            face_id = face.get("FaceId")
            if not face_id:
                continue
            slug = _get_slug_for_face_id(conn, face_id)
            if slug:
                people.add(slug)
    finally:
        conn.close()

    logger.info("People found: %s", people)

    if socket_id:
        _notify_ui(socket_id, people)

    return
