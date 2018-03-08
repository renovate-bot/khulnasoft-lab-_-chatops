# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Slack::FileUpload do
  let(:file) do
    file = Tempfile.new(['.txt'])

    file.write('hello')
    file.rewind
    file
  end

  let(:file_upload) do
    described_class.new(
      file: file,
      type: :txt,
      channel: '123',
      token: 'hunter2',
      title: 'Example File'
    )
  end

  after do
    file.close
  end

  describe '#upload' do
    context 'when Slack responds with an HTTP 200 OK' do
      it 'returns nil' do
        response =
          instance_double('response', status: 200, body: JSON.dump(ok: true))

        expect(HTTP)
          .to receive(:post)
          .with(
            described_class::UPLOAD_URL,
            form: {
              token: 'hunter2',
              channels: '123',
              file: an_instance_of(HTTP::FormData::File),
              filename: File.basename(file.path),
              filetype: :txt,
              title: 'Example File'
            }
          )
          .and_return(response)

        expect(file_upload.upload).to be_nil
      end
    end

    context 'when Slack responds with an error' do
      it 'raises UploadError' do
        response =
          instance_double('response', status: 200, body: JSON.dump(ok: false))

        expect(HTTP)
          .to receive(:post)
          .with(
            described_class::UPLOAD_URL,
            form: {
              token: 'hunter2',
              channels: '123',
              file: an_instance_of(HTTP::FormData::File),
              filename: File.basename(file.path),
              filetype: :txt,
              title: 'Example File'
            }
          )
          .and_return(response)

        expect { file_upload.upload }
          .to raise_error(described_class::UploadError)
      end
    end
  end
end
