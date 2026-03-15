from config import Config
import os
from dotenv import load_dotenv

load_dotenv()
print(f"ENV DATABASE_URL: {os.environ.get('DATABASE_URL')}")
print(f"CONFIG DATABASE_URL: {Config.DATABASE_URL}")
