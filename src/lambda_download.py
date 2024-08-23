import os
import boto3
import logging
import base64

logger = logging.getLogger()

def handler(event, context):

    folder_name = event['pathParameters']['folder'] 
    file_name = event['pathParameters']['item']
    bucket_name = os.environ['BUCKET_NAME']

    logger.info('folder_name: %s', folder_name)
    logger.info('bucket_name: %s', bucket_name)

    client = boto3.client('s3')
    response = client.get_object(
        Bucket=bucket_name,
        Key=f'{folder_name}/{file_name}')

    file = response['Body'].read()
    file_encoded = base64.b64encode(file)

    # Allowing CORS for Proxy Integration
    return {
        'statusCode': 200,
        'body': file_encoded,
        'headers': {
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
        },
    }
