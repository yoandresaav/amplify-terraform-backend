"""
This lambda only get each chunk and save in S3 bucket.
And return all ok to the client
"""
import os
import json
import boto3
from botocore.exceptions import ClientError

s3_client = boto3.client('s3')
cognito_client = boto3.client('cognito-idp')

def handler(event, context):
    token = event['headers'].get('Authorization')
    if not token:
        return {
            'statusCode': 401,
            'body': json.dumps('Unauthorized: No token provided')
        }

    # Verify the token
    user_pool_id = os.environ['USER_POOL_ID']
    try:
        response = cognito_client.get_user(
            AccessToken=token
        )
        username = response['Username']
    except ClientError as e:
        return {
            'statusCode': 401,
            'body': json.dumps('Unauthorized: Invalid token')
        }

    # Get the file details from the event
    body = json.loads(event['body'])
    file_chunk = body.get('file_chunk')
    chunk_number = body.get('chunk_number')
    total_chunks = body.get('total_chunks')
    file_key = body.get('file_key')

    if not file_chunk or chunk_number is None or total_chunks is None or not file_key:
        return {
            'statusCode': 400,
            'body': json.dumps('Bad Request: Missing required parameters')
        }

    # Upload the chunk to S3
    bucket_name = os.environ['BUCKET_NAME']
    chunk_key = f"{file_key}/chunk_{chunk_number}"

    try:
        s3_client.put_object(
            Bucket=bucket_name,
            Key=chunk_key,
            Body=file_chunk
        )
    except ClientError as e:
        return {
            'statusCode': 500,
            'body': json.dumps(f"Error uploading chunk: {str(e)}")
        }

    # Check if all chunks are uploaded
    if chunk_number == total_chunks:
        # Trigger assembly of the file
        # This can be done via S3 event or another mechanism
        pass

    return {
        'statusCode': 200,
        'body': json.dumps(f'Chunk {chunk_number} uploaded successfully')
    }

