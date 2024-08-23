import os
import json
import boto3

BUCKET_NAME = os.environ["BUCKET_NAME"]
s3_client = boto3.client('s3')

def download_s3(key: str) -> bytes:
    """Download an object from the S3 bucket"""
    obj = s3_client.get_object(Bucket=BUCKET_NAME, Key=key)
    return obj["Body"].read()

def handler(event, context):
    body = json.loads(event['body'])

    # List with the keys of the files to be assembled
    files_name = body['files_name']
    # Number of files
    total_chunks = body['total_chunks']
    # Folder where the files are stored
    folder = body['folder'] 

    all_files = {}

    for file_name in files_name:
        file_key = file_name.split("._part_")[0]
        if file_key not in all_files:
            all_files[file_key] = [file_name]
        else:
            all_files[file_key].append(file_name)

    for file_key, files_name in all_files.items():
        combined_stream = b''
        for file_name in files_name:
            _file_key = f"{folder}/{file_name}"
            combined_stream += download_s3(_file_key)
            # Delete the chunk after it has been assembled
            s3_client.delete_object(Bucket=BUCKET_NAME, Key=_file_key)

        # Upload the assembled file back to S3
        s3_client.put_object(Bucket=BUCKET_NAME, Key=f"{folder}/{file_key}", Body=combined_stream)



    return {
        'statusCode': 200,
        'body': f"File assembled successfully and stored",
        'headers': {
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
        },
    }

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
        'body': f"File assembled successfully and stored at {assembled_file_key}",
        'headers': {
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
        },
    }

