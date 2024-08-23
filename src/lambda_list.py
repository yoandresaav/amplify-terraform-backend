import logging
import os
import boto3
import json

logger = logging.getLogger()

def handler(event, context):
    folder_name = event['queryStringParameters']['folder'] 
    bucket_name = os.environ['BUCKET_NAME']

    logger.info('folder_name: %s', folder_name)
    logger.info('bucket_name: %s', bucket_name)

    print(folder_name)
    print(bucket_name)

    client = boto3.client('s3')
    response = client.list_objects(
        Bucket=bucket_name,
        Prefix=folder_name)

    files = []
    for obj in response.get('Contents', []):
        file = obj['Key']
        file = file.replace(f'{folder_name}/', '')
        files.append(file)

    # Allowing CORS for Proxy Integration
    return {
        'statusCode': 200,
        'body': json.dumps(files),
        'headers': {
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
        },
    }
