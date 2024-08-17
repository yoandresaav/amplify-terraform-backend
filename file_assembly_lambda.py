import os
import boto3

s3_client = boto3.client('s3')

def handler(event, context):
    bucket_name = os.environ['BUCKET_NAME']
    file_key = event['file_key']
    total_chunks = event['total_chunks']

    assembled_file_key = f"{file_key}/assembled_file"

    # Create an empty file to write to
    assembled_file = b''

    # Download and append each chunk
    for chunk_number in range(1, total_chunks + 1):
        chunk_key = f"{file_key}/chunk_{chunk_number}"
        try:
            chunk_obj = s3_client.get_object(Bucket=bucket_name, Key=chunk_key)
            assembled_file += chunk_obj['Body'].read()
        except ClientError as e:
            return {
                'statusCode': 500,
                'body': f"Error fetching chunk {chunk_number}: {str(e)}"
            }

    # Upload the assembled file back to S3
    try:
        s3_client.put_object(Bucket=bucket_name, Key=assembled_file_key, Body=assembled_file)
    except ClientError as e:
        return {
            'statusCode': 500,
            'body': f"Error uploading assembled file: {str(e)}"
        }

    return {
        'statusCode': 200,
        'body': f"File assembled successfully and stored at {assembled_file_key}"
    }

